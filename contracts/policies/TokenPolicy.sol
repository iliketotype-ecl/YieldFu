// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/DEBASE.sol";

contract TokenPolicy is Policy {
    YieldFuToken public token;
    DEBASE public debaseModule; // Reference to the DEBASE module

    constructor(Kernel kernel_) Policy(kernel_) {
        token = YieldFuToken(getModuleAddress(toKeycode("TOKEN")));
        debaseModule = DEBASE(getModuleAddress(toKeycode("DBASE"))); // Initialize the DEBASE module
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2); 
        dependencies[0] = toKeycode("TOKEN");
        dependencies[1] = toKeycode("DBASE"); // Add DEBASE as a dependency
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](3);
        requests[0] = Permissions(toKeycode("TOKEN"), token.transfer.selector);
        requests[1] = Permissions(toKeycode("TOKEN"), token.transferFrom.selector);
        requests[2] = Permissions(toKeycode("DBASE"), debaseModule.debase.selector); // Request permission for debase
    }

    function transfer(address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        token.transferFrom(from, to, amount);
    }

    function debase() external {
        debaseModule.debase(); // Call debase from the DEBASE module
    }
}
