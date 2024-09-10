// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/BOND.sol";

contract BondingPolicy is Policy {
    BOND public bonding;

    constructor(Kernel kernel_) Policy(kernel_) {
        bonding = BOND(getModuleAddress(toKeycode("BONDS")));
    }

    function configureDependencies() external pure override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("BONDS");
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](4);
        requests[0] = Permissions(toKeycode("BONDS"), BOND.bondEth.selector);
        requests[1] = Permissions(toKeycode("BONDS"), BOND.bondPartnerToken.selector);
        requests[2] = Permissions(toKeycode("BONDS"), BOND.claimBond.selector);
        requests[3] = Permissions(toKeycode("BONDS"), BOND.changeDiscount.selector);
    }

    function bondEth() external payable {
        bonding.bondEth{value: msg.value}();
    }

    function bondPartnerToken(address tokenAddress, uint256 amount) external {
        bonding.bondPartnerToken(tokenAddress, amount);
    }

    function claimBond() external {
        bonding.claimBond();
    }

    function changeDiscount(bool isEth, uint256 newDiscount) external {
        bonding.changeDiscount(isEth, newDiscount);
    }
}