// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SatlayerPool} from "../src/SatlayerPool.sol"; 

contract DeploySatlayerPoolSepolia is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 DECIMALS = 10**18;

        vm.startBroadcast(deployerPrivateKey);

        // can grab testnet tokens to play around with app here:
        // https://stg.secured.finance/faucet/
        address[] memory tokensAllowed = new address[](3);
        tokensAllowed[0] = 0xF31B086459C2cdaC006Feedd9080223964a9cDdB; // "USDC"
        tokensAllowed[1] = 0xB2a6874c2F71fD4481674BaC945D5407A2318b3E; // "WBTC"
        tokensAllowed[2] = 0x50AeD9269cc4D459567Cf9de2D08984229b8754F; // "WFIL"

        uint256[] memory caps = new uint256[](3);
        caps[0] = 100000 * DECIMALS;
        caps[1] = 200 * DECIMALS;
        caps[2] = 4200 * DECIMALS;

        uint256[] memory individualCaps = new uint256[](3);
        individualCaps[0] = uint256(0x0);
        individualCaps[1] = uint256(0x0);
        individualCaps[2] = uint256(0x0);

        string[] memory names = new string[](3);
        names[0] = "SatLayer USDC";
        names[1] = "Satlayer WBTC";
        names[2] = "Satlayer WFIL";

        string[] memory symbols = new string[](3);
        symbols[0] = "satUSDC";
        symbols[1] = "satWBTC";
        symbols[2] = "satWFIL";      

        SatlayerPool pool = new SatlayerPool(tokensAllowed, caps, individualCaps, names, symbols);
        
        console.log("SatlayerPool deployed to:", address(pool));
        vm.stopBroadcast();
    }
}
