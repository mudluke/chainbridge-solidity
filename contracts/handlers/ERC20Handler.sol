pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "../interfaces/IDepositExecute.sol";
import "./HandlerHelpers.sol";
import "../ERC20Safe.sol";
import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

/**
    @title Handles ERC20 deposits and deposit executions.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract ERC20Handler is IDepositExecute, HandlerHelpers, ERC20Safe {
    bool public _useContractWhitelist;

    struct DepositRecord {
        address _tokenAddress;
        uint8   _destinationChainID;
        bytes32 _resourceID;
        uint    _lenDestinationRecipientAddress;
        bytes   _destinationRecipientAddress;
        address _depositer;
        uint    _amount;
    }

    // depositNonce => Deposit Record
    mapping (uint8 => mapping(uint256 => DepositRecord)) public _depositRecords;

    /**
        @param bridgeAddress Contract address of previously deployed Bridge.
        @param initialResourceIDs Resource IDs are composed of chain ID + contract address, and used to identify a specific contract address.
        These are the Resource IDs this contract will initially support.
        @param initialContractAddresses These are the addresses the {initialResourceIDs} will point to, and are the contracts that will be
        called to perform various deposit calls.
        @param burnableContractAddresses These addresses will be set as burnable and when {deposit} is called, the deposited token will be burned.
        When {executeDeposit} is called, new tokens will be minted.

        @dev {initialResourceIDs} and {initialContractAddresses} must have the same length (one resourceID for every address).
        Also, these arrays must be ordered in the way that {initialResourceIDs}[0] is the intended resourceID for {initialContractAddresses}[0].
     */
    constructor(
        address          bridgeAddress,
        bytes32[] memory initialResourceIDs,
        address[] memory initialContractAddresses,
        address[] memory burnableContractAddresses
    ) public {
        require(initialResourceIDs.length == initialContractAddresses.length,
            "mismatch length between initialResourceIDs and initialContractAddresses");

        _bridgeAddress = bridgeAddress;

        for (uint256 i = 0; i < initialResourceIDs.length; i++) {
            _setResource(initialResourceIDs[i], initialContractAddresses[i]);
        }

        for (uint256 i = 0; i < burnableContractAddresses.length; i++) {
            _setBurnable(burnableContractAddresses[i]);
        }
    }

    /**
        @param depositID This ID will have been generated by the Bridge contract.
        @param destId ID of chain deposit will be bridged to.
        @return DepositRecord which consists of:
        - _tokenAddress Address used when {deposit} was executed.
        - _destinationChainID ChainID deposited tokens are intended to end up on.
        - _resourceID ResourceID used when {deposit} was executed.
        - _lenDestinationRecipientAddress Used to parse recipient's address from {_destinationRecipientAddress}
        - _destinationRecipientAddress Address tokens are intended to be deposited to on desitnation chain.
        - _depositer Address that initially called {deposit} in the Bridge contract.
        - _amount Amount of tokens that were deposited.
    */
    function getDepositRecord(uint256 depositID, uint8 destId) public view returns (DepositRecord memory) {
        return _depositRecords[destId][depositID];
    }

    /**
        @notice A deposit is initiatied by making a deposit in the Bridge contract.
        @param destinationChainID Chain ID of chain tokens are expected to be bridged to.
        @param depositNonce This value is generated as an ID by the Bridge contract.
        @param depositer Address of account making the deposit in the Bridge contract.
        @param data Consists of: {resourceID}, {amount}, {lenRecipientAddress}, and {recipientAddress}
        all padded to 32 bytes.
        @notice Data passed into the function should be constructed as follows:

        resourceID                  bytes32     bytes   0 - 32
        amount                      uint256     bytes  32 - 64
        recipientAddress length     uint256     bytes  64 - 96
        recipientAddress            bytes       bytes  96 - END
        @dev Depending if the corresponding {tokenAddress} for the parsed {resourceID} is
        marked true in {_burnList}, deposited tokens will be burned, if not, they will be locked.
     */
    function deposit(
        uint8 destinationChainID,
        uint256 depositNonce,
        address depositer,
        bytes memory data
    ) public override _onlyBridge {
        bytes32        resourceID;
        bytes   memory recipientAddress;
        uint256        amount;
        uint256        lenRecipientAddress;

        assembly {

            resourceID := mload(add(data, 0x20))
            amount := mload(add(data, 0x40))

            recipientAddress := mload(0x40)
            lenRecipientAddress := mload(add(0x60, data))
            mstore(0x40, add(0x20, add(recipientAddress, lenRecipientAddress)))

            calldatacopy(
                recipientAddress, // copy to destinationRecipientAddress
                0xE4, // copy from calldata @ 0x104
                sub(calldatasize(), 0xE4) // copy size (calldatasize - 0x104)
            )
        }

        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
        require(_contractWhitelist[tokenAddress], "provided tokenAddress is not whitelisted");

        if (_burnList[tokenAddress]) {
            burnERC20(tokenAddress, depositer, amount);
        } else {
            lockERC20(tokenAddress, depositer, address(this), amount);
        }

        _depositRecords[destinationChainID][depositNonce] = DepositRecord(
            tokenAddress,
            destinationChainID,
            resourceID,
            lenRecipientAddress,
            recipientAddress,
            depositer,
            amount
        );
    }

    /**
        @notice Deposit execution should be initiated when a proposal is executed in the Bridge contract.
        by a relayer on the deposit's destination chain.
        @param data Consists of {resourceID}, {amount}, {lenDestinationRecipientAddress},
        and {destinationRecipientAddress} all padded to 32 bytes.
        @notice Data passed into the function should be constructed as follows:
        resourceID                             bytes32     bytes  0 - 32
        amount                                 uint256     bytes  32 - 64
        destinationRecipientAddress length     uint256     bytes  64 - 96
        destinationRecipientAddress            bytes       bytes  96 - END
     */
    function executeDeposit(bytes memory data) public override _onlyBridge {
        uint256       amount;
        bytes32       resourceID;
        bytes  memory destinationRecipientAddress;


        assembly {
            resourceID := mload(add(data, 0x20))
            amount := mload(add(data, 0x40))

            destinationRecipientAddress := mload(0x40)
            let lenDestinationRecipientAddress := mload(add(0x60, data))
            mstore(0x40, add(0x20, add(destinationRecipientAddress, lenDestinationRecipientAddress)))

            // in the calldata the destinationRecipientAddress is stored at 0xC4 after accounting for the function signature and length declaration
            calldatacopy(
                destinationRecipientAddress, // copy to destinationRecipientAddress
                0x84, // copy from calldata @ 0x84
                sub(calldatasize(), 0x84) // copy size to the end of calldata
            )
        }

        bytes20 recipientAddress;
        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];

        assembly {
            recipientAddress := mload(add(destinationRecipientAddress, 0x20))
        }

        require(_contractWhitelist[tokenAddress], "provided tokenAddress is not whitelisted");

        if (_burnList[tokenAddress]) {
            mintERC20(tokenAddress, address(recipientAddress), amount);
        } else {
            releaseERC20(tokenAddress, address(recipientAddress), amount);
        }
    }

    /**
        @notice Not yet callable by current Bridge contract.
     */
    function withdraw(address tokenAddress, address recipient, uint amount) public _onlyBridge {
        releaseERC20(tokenAddress, recipient, amount);
    }
}
