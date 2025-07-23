import "dotenv/config";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.30",
        settings: {
            optimizer: {
                enabled: true, 
                runs: 200, 
            },
            evmVersion: "shanghai"
        },
    },
    networks: {
        // Local Hardhat network (default)
        hardhat: {},
        // Goerli testnet configuration
        goerli: {
            url: process.env.GOERLI_RPC_URL || "", // From environment variable get RPC URL
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [], // From environment variable get private key
        },
        // Sepolia testnet configuration
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL || "",
            accounts:
                process.env.SEPOLIA_PRIVATE_KEY !== undefined
                    ? [process.env.SEPOLIA_PRIVATE_KEY]
                    : [],
        },

        // World Chain Sepolia configuration
        worldchainSepolia: {
            url: "https://worldchain-sepolia.g.alchemy.com/public", // World Chain Sepolia RPC URL
            chainId: 4801, // World Chain Sepolia Chain ID
            accounts:
                process.env.SEPOLIA_PRIVATE_KEY !== undefined
                    ? [process.env.SEPOLIA_PRIVATE_KEY]
                    : [],
        },

        // World Chain Mainnet configuration
        worldchainMainnet: {
            url: "https://worldchain-mainnet.g.alchemy.com/public", // World Chain Mainnet RPC URL
            chainId: 480, // World Chain Mainnet Chain ID
            accounts:
                process.env.MAINNET_PRIVATE_KEY !== undefined
                    ? [process.env.MAINNET_PRIVATE_KEY]
                    : [],
        },
    },
    // You can add etherscan verification configuration, etc.
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY, // Etherscan API Key
    },
};

export default config;
