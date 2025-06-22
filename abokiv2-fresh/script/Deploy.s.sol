// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/Abokiv2.sol";

contract DeployAbokiv2 is Script {
    // Base Mainnet Uniswap V3 addresses 
    address constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; //
    address constant QUOTER_V2 = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;        // 
    address constant WETH = 0x4200000000000000000000000000000000000006;             // 
    
    // Base mainnet tokens
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;   // Native USDC
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;  // Bridged USDC
    
    function run() external {
        // Get deployment parameters from environment
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 protocolFeePercent = vm.envUint("PROTOCOL_FEE_PERCENT");
        
        vm.startBroadcast();
        
        console.log("Deploying Abokiv2 to Base Mainnet...");
        console.log("Treasury:", treasury);
        console.log("Protocol Fee:", protocolFeePercent, "basis points");
        
        // Deploy the contract
        Abokiv2 aboki = new Abokiv2(treasury, protocolFeePercent);
        
        console.log("Abokiv2 deployed at:", address(aboki));
        
        // Configure the contract
        console.log("Configuring Uniswap V3 integration...");
        
        aboki.setUniswapRouter(UNISWAP_V3_ROUTER);
        console.log("Router set:", UNISWAP_V3_ROUTER);
        
        aboki.setQuoter(QUOTER_V2);
        console.log("Quoter set:", QUOTER_V2);
        
        aboki.setWETH(WETH);
        console.log("WETH set:", WETH);
        
        // Add supported tokens
        aboki.setTokenSupport(USDC, true);
        console.log("Native USDC supported:", USDC);
        
        aboki.setTokenSupport(USDbC, true);
        console.log("Bridged USDbC supported:", USDbC);
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Contract Address:", address(aboki));
        console.log("Network: Base Mainnet (Chain ID: 8453)");
        console.log("Treasury:", treasury);
        console.log("Protocol Fee:", protocolFeePercent, "bps");
        console.log("Uniswap V3 Router:", UNISWAP_V3_ROUTER);
        console.log("Quoter V2:", QUOTER_V2);
        console.log("WETH:", WETH);
        console.log("=========================");
    }
}