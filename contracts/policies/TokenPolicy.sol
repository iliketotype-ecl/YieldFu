// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/DEBASE.sol";

contract TokenPolicy is Policy {
    DEBASE public token;

    constructor(Kernel kernel_) Policy(kernel_) {
        token = DEBASE(getModuleAddress(toKeycode("TOKEN")));
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TOKEN");
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("TOKEN"), token.transfer.selector);
        requests[1] = Permissions(toKeycode("TOKEN"), token.transferFrom.selector);
    }

    function transfer(address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        token.transferFrom(from, to, amount);
    }

    function debase() external {
        token.debase();
    }
}