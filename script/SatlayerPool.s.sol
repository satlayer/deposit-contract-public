// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SatlayerPool} from "../src/SatlayerPool.sol"; 

contract DeploySatlayerPoolSepolia is Script {
    function setUp() public {}

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 DECIMALS = 10**8;

        //vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();

        // can grab testnet tokens to play around with app here:
        // https://stg.secured.finance/faucet/
        address[] memory tokensAllowed = new address[](4);
        tokensAllowed[0] = 0xC96dE26018A54D51c097160568752c4E3BD6C364; // FBTC
        tokensAllowed[1] = 0x8236a87084f8B84306f72007F36F2618A5634494; // LBTC
        tokensAllowed[2] = 0xd9D920AA40f578ab794426F5C90F6C731D159DEf; // solvBTC.BBN
        tokensAllowed[3] = 0xF469fBD2abcd6B9de8E169d128226C0Fc90a012e; // pumpBTC

        uint256[] memory caps = new uint256[](4); // set all caps initially to 1 BTC
        caps[0] = DECIMALS;
        caps[1] = DECIMALS;
        caps[2] = 10**18; // solvBTC.BBN has a decimel precision of 18
        caps[3] = DECIMALS;

        string[] memory names = new string[](4);
        names[0] = "SatLayer FBTC";
        names[1] = "Satlayer LBTC";
        names[2] = "Satlayer SolvBTC.BBN";
        names[3] = "Satlayer pumpBTC";

        string[] memory symbols = new string[](4);
        symbols[0] = "satFBTC";
        symbols[1] = "satLBTC";
        symbols[2] = "satSolvBTC";      
        symbols[3] = "satPumpBTC";  

        SatlayerPool pool = new SatlayerPool(tokensAllowed, caps, names, symbols);
        
        console.log("SatlayerPool deployed to:", address(pool));
        vm.stopBroadcast();
    }
}
