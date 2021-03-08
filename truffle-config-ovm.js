/**
 * Copyright 2020 ChainSafe Systems
 * SPDX-License-Identifier: LGPL-3.0-only
 */

/**
 * Truffle config specifically for Optimistic Ethereum (OVM) 
 */

const GAS_LIMIT = 8999999
const GAS_PRICE = '0'

module.exports = {
  contracts_build_directory: './build/contracts/ovm',
  plugins: ["solidity-coverage"],
  networks: {

    test: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "420",       // optimistic-integration default chain ID
      gas: GAS_LIMIT,
      gasPrice: GAS_PRICE
     },
    gas: GAS_LIMIT,
    gasPrice: GAS_PRICE
  },

  compilers: {
    solc: {
      version: "node_modules/@eth-optimism/solc",       
      settings: {
        optimizer: {
          enabled: true,
          runs: 1
        },
      }
    }
  }
}
