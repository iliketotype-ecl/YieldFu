// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../Kernel.sol";

/// @notice TRSRY manages protocol funds, handles debt, and allows approved withdrawals.
contract TRSRY is Module, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  EVENTS ========= //
    event WithdrawApprovalSet(address indexed withdrawer, IERC20 indexed token, uint256 amount);
    event DebtApprovalSet(address indexed debtor, IERC20 indexed token, uint256 amount);
    event Withdrawal(address indexed policy, address indexed withdrawer, IERC20 indexed token, uint256 amount);
    event DebtIncurred(IERC20 indexed token, address indexed policy, uint256 amount);
    event DebtRepaid(IERC20 indexed token, address indexed policy, uint256 amount);
    event DebtSet(IERC20 indexed token, address indexed policy, uint256 amount);
    event TreasuryActivated();
    event TreasuryDeactivated();

    // =========  ERRORS ========= //
    error TRSRY_NotActive();
    error TRSRY_WithdrawalNotApproved();
    error TRSRY_DebtNotApproved();
    error TRSRY_NoDebtOutstanding();

    // =========  STATE ========= //
    bool public active;
    mapping(address => mapping(IERC20 => uint256)) public withdrawApproval;
    mapping(address => mapping(IERC20 => uint256)) public debtApproval;
    mapping(IERC20 => uint256) public totalDebt;
    mapping(IERC20 => mapping(address => uint256)) public reserveDebt;

    // =========  CONSTRUCTOR ========= //
    constructor(Kernel kernel_) Module(kernel_) {
        active = true;
    }

    // =========  MODULE INTERFACE ========= //
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1);
    }

    // =========  MODIFIERS ========= //
    modifier onlyWhileActive() {
        if (!active) revert TRSRY_NotActive();
        _;
    }

    // =========  TREASURY FUNCTIONS ========= //
    /// @notice Set withdrawal approval for a withdrawer
    function setWithdrawApproval(address withdrawer, IERC20 token, uint256 amount) external permissioned {
        withdrawApproval[withdrawer][token] = amount;
        emit WithdrawApprovalSet(withdrawer, token, amount);
    }

    /// @notice Withdraw from reserves for pre-approved withdrawers
    function withdrawReserves(address to, IERC20 token, uint256 amount) external onlyWhileActive nonReentrant permissioned {
        if (withdrawApproval[msg.sender][token] < amount) revert TRSRY_WithdrawalNotApproved();
        withdrawApproval[msg.sender][token] -= amount;
        token.safeTransfer(to, amount);
        emit Withdrawal(msg.sender, to, token, amount);
    }

    /// @notice Set debt approval for a debtor
    function setDebtApproval(address debtor, IERC20 token, uint256 amount) external permissioned {
        debtApproval[debtor][token] = amount;
        emit DebtApprovalSet(debtor, token, amount);
    }

    /// @notice Allow an approved policy to incur debt
    function incurDebt(IERC20 token, uint256 amount) external onlyWhileActive nonReentrant permissioned {
        if (debtApproval[msg.sender][token] < amount) revert TRSRY_DebtNotApproved();
        debtApproval[msg.sender][token] -= amount;
        totalDebt[token] += amount;
        reserveDebt[token][msg.sender] += amount;
        token.safeTransfer(msg.sender, amount);
        emit DebtIncurred(token, msg.sender, amount);
    }

    /// @notice Repay debt
    function repayDebt(IERC20 token, uint256 amount) external nonReentrant {
        if (reserveDebt[token][msg.sender] < amount) revert TRSRY_NoDebtOutstanding();
        reserveDebt[token][msg.sender] -= amount;
        totalDebt[token] -= amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit DebtRepaid(token, msg.sender, amount);
    }

    /// @notice Set debt in case of emergencies
    function setDebt(address debtor, IERC20 token, uint256 amount) external permissioned {
        reserveDebt[token][debtor] = amount;
        emit DebtSet(token, debtor, amount);
    }

    /// @notice Get the current reserve balance
    function getReserveBalance(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this)) + totalDebt[token];
    }

    /// @notice Emergency shutdown of withdrawals and debt
    function deactivate() external permissioned {
        active = false;
        emit TreasuryDeactivated();
    }

    /// @notice Re-activate after shutdown
    function activate() external permissioned {
        active = true;
        emit TreasuryActivated();
    }
}