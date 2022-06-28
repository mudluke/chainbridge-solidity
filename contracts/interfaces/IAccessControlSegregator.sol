// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

/**
    @title Interface to be used with contracts that want per function access control.
    @author ChainSafe Systems.
 */
interface IAccessControlSegregator {
    /**
        @notice Returns boolean value if account has access to function.
        @param func Function name.
        @param account Address of account.
        @return Boolean value depending if account has access.
    */
    function hasAccess(string func, address account) public;
}
