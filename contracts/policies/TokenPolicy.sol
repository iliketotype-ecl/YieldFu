// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/MINTR.sol";
import "../modules/DEBASE.sol";
import "../YieldFu.sol";
import "hardhat/console.sol"; // Keep this for logging

contract TokenPolicy is Policy {
    YieldFuToken public yieldFuToken;
    MINTR public mintrModule;
    DEBASE public debaseModule;
    mapping(address => bool) public authorizedMinters;
    
    error TokenPolicy_NotAuthorized();

    event MinterAuthorized(address indexed minter);
    event MinterDeauthorized(address indexed minter);

    constructor(Kernel kernel_, YieldFuToken yieldFuToken_) Policy(kernel_) {
        yieldFuToken = yieldFuToken_;
        mintrModule = MINTR(getModuleAddress(toKeycode("MINTR")));
        debaseModule = DEBASE(getModuleAddress(toKeycode("DBASE")));
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("DBASE");
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](3);
        requests[0] = Permissions(toKeycode("MINTR"), mintrModule.mint.selector);
        requests[1] = Permissions(toKeycode("MINTR"), mintrModule.burn.selector);
        requests[2] = Permissions(toKeycode("DBASE"), debaseModule.debase.selector);
    }


    // New function to authorize minters
    function authorizeMinter(address minter) external onlyExecutor {
        authorizedMinters[minter] = true;
        emit MinterAuthorized(minter);
    }

    // New function to deauthorize minters
    function deauthorizeMinter(address minter) external onlyExecutor {
        authorizedMinters[minter] = false;
        emit MinterDeauthorized(minter);
    }

    function changeDebaseRate(uint256 newRate) external {
    // Assuming permission checks have been done via Kernel
        debaseModule.changeDebaseRate(newRate);
    }


    // Mint function with user-level permission check

    function mint(address to_, uint256 amount_) external {
        console.log("TOKENPOLICY: Mint called by:");
        console.logAddress(msg.sender);
        console.log("TOKENPOLICY: Amount:");
        console.logUint(amount_);
        console.log("TOKENPOLICY: To:");
        console.logAddress(to_);
        
        console.log("TOKENPOLICY: Checking if caller is authorized to mint");
        bool isAuthorized = isAuthorizedMinter(msg.sender);
        console.logBool(isAuthorized);
        
        if (!isAuthorized) revert TokenPolicy_NotAuthorized();
        console.log("TOKENPOLICY: Authorized minter");
        
        console.log("TOKENPOLICY: Calling MINTR mint");
        MINTR(getModuleAddress(toKeycode("MINTR"))).mint(to_, amount_);
    }

    // Burn function using centralized permission management
    function burn(address from, uint256 amount) external {
        console.log("TokenPolicy: Attempting to burn", amount, "tokens from", from);

        if (!kernel.modulePermissions(toKeycode("MINTR"), this, mintrModule.burn.selector)) {
            console.log("TokenPolicy: Unauthorized call to burn");
            revert TokenPolicy_NotAuthorized();
        }

        mintrModule.burn(from, amount);
    }

    // Debase function using centralized permission management
    function debase() external {
        console.log("TokenPolicy: Attempting to debase");

        if (!kernel.modulePermissions(toKeycode("DBASE"), this, debaseModule.debase.selector)) {
            console.log("TokenPolicy: Unauthorized call to debase");
            revert TokenPolicy_NotAuthorized();
        }

        debaseModule.debase();
    }

    // Helper function to check if an address is an authorized minter
    function isAuthorizedMinter(address minter) public view returns (bool) {
        return authorizedMinters[minter];
    }

    // Only allow the Kernel's executor to call certain functions
    modifier onlyExecutor() {
        require(msg.sender == kernel.executor(), "TokenPolicy: caller is not the executor");
        _;
    }
}