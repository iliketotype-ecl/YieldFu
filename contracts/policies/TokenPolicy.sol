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

    error Unauthorized();

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

    // Mint function using centralized permission management
    function mint(address to, uint256 amount) external {
        console.log("TokenPolicy: Attempting to mint", amount, "tokens for", to);
        console.log("TokenPolicy: Caller is", msg.sender);

        // Check permissions through the Kernel
        if (!kernel.modulePermissions(toKeycode("MINTR"), this, mintrModule.mint.selector)) {
            console.log("TokenPolicy: Unauthorized call to mint");
            revert Unauthorized();
        }

        // If permission is granted, proceed with minting
        mintrModule.mint(msg.sender, to, amount);
    }

    // Burn function using centralized permission management
    function burn(address from, uint256 amount) external {
        console.log("TokenPolicy: Attempting to burn", amount, "tokens from", from);

        // Check permissions through the Kernel
        if (!kernel.modulePermissions(toKeycode("MINTR"), this, mintrModule.burn.selector)) {
            console.log("TokenPolicy: Unauthorized call to burn");
            revert Unauthorized();
        }

        // If permission is granted, proceed with burning
        mintrModule.burn(from, amount);
    }

    // Debase function using centralized permission management
    function debase() external {
        console.log("TokenPolicy: Attempting to debase");

        // Check permissions through the Kernel
        if (!kernel.modulePermissions(toKeycode("DBASE"), this, debaseModule.debase.selector)) {
            console.log("TokenPolicy: Unauthorized call to debase");
            revert Unauthorized();
        }

        // If permission is granted, proceed with debasing
        debaseModule.debase();
    }
}
