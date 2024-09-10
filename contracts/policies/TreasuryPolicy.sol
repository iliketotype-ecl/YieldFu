// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/TRSRY.sol";

contract TreasuryPolicy is Policy {
    TRSRY public treasury;

    constructor(Kernel kernel_) Policy(kernel_) {
        treasury = TRSRY(getModuleAddress(toKeycode("TRSRY")));
    }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TRSRY");
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](6); 
        requests[0] = Permissions(toKeycode("TRSRY"), treasury.increaseWithdrawApproval.selector);
        requests[1] = Permissions(toKeycode("TRSRY"), treasury.decreaseWithdrawApproval.selector);
        requests[2] = Permissions(toKeycode("TRSRY"), treasury.withdrawReserves.selector);
        requests[3] = Permissions(toKeycode("TRSRY"), treasury.increaseDebtorApproval.selector);
        requests[4] = Permissions(toKeycode("TRSRY"), treasury.decreaseDebtorApproval.selector);
        requests[5] = Permissions(toKeycode("TRSRY"), treasury.repayDebt.selector);
    }

    /// @notice Withdraw funds from Treasury
    function withdrawFromTreasury(address to, ERC20 token, uint256 amount) external {
        treasury.withdrawReserves(to, token, amount);
    }

    /// @notice Increase approval for a withdrawer in the TRSRY module
    function increaseWithdrawApproval(address withdrawer, ERC20 token, uint256 amount) external {
        treasury.increaseWithdrawApproval(withdrawer, token, amount);
    }

    /// @notice Decrease approval for a withdrawer in the TRSRY module
    function decreaseWithdrawApproval(address withdrawer, ERC20 token, uint256 amount) external {
        treasury.decreaseWithdrawApproval(withdrawer, token, amount);
    }

    /// @notice Authorize a debtor to incur debt within the Treasury
    function authorizeDebt(address debtor, ERC20 token, uint256 amount) external {
        treasury.increaseDebtorApproval(debtor, token, amount);
    }

    /// @notice Reduce authorization for a debtor
    function reduceDebtAuthorization(address debtor, ERC20 token, uint256 amount) external {
        treasury.decreaseDebtorApproval(debtor, token, amount);
    }

    /// @notice Repay debt through the TRSRY module
    function repayDebt(address debtor, ERC20 token, uint256 amount) external {
        treasury.repayDebt(debtor, token, amount);
    }

    /// @notice Get current reserve balance from Treasury
    function getTreasuryBalance(ERC20 token) external view returns (uint256) {
        return treasury.getReserveBalance(token);
    }
}
