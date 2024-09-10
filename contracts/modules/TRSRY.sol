// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Kernel.sol";

/// @notice TRSRY manages protocol funds, handles debt, and allows approved withdrawals.
contract TRSRY is Module {
    // =========  EVENTS ========= //
    event IncreaseWithdrawApproval(address indexed withdrawer_, ERC20 indexed token_, uint256 newAmount_);
    event DecreaseWithdrawApproval(address indexed withdrawer_, ERC20 indexed token_, uint256 newAmount_);
    event Withdrawal(address indexed policy_, address indexed withdrawer_, ERC20 indexed token_, uint256 amount_);
    event IncreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DecreaseDebtorApproval(address indexed debtor_, ERC20 indexed token_, uint256 newAmount_);
    event DebtIncurred(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtRepaid(ERC20 indexed token_, address indexed policy_, uint256 amount_);
    event DebtSet(ERC20 indexed token_, address indexed policy_, uint256 amount_);

    // =========  STATE ========= //
    bool public active;
    mapping(address => mapping(ERC20 => uint256)) public withdrawApproval;
    mapping(address => mapping(ERC20 => uint256)) public debtApproval;
    mapping(ERC20 => uint256) public totalDebt;
    mapping(ERC20 => mapping(address => uint256)) public reserveDebt;

    // =========  MODIFIERS ========= //
    modifier onlyWhileActive() {
        require(active, "TRSRY: Not active");
        _;
    }

    constructor(Kernel kernel_) Module(kernel_) {
        active = true;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    /// @notice Increase approval for a withdrawer
    function increaseWithdrawApproval(address withdrawer_, ERC20 token_, uint256 amount_) external permissioned {
        withdrawApproval[withdrawer_][token_] += amount_;
        emit IncreaseWithdrawApproval(withdrawer_, token_, withdrawApproval[withdrawer_][token_]);
    }

    /// @notice Decrease approval for a withdrawer
    function decreaseWithdrawApproval(address withdrawer_, ERC20 token_, uint256 amount_) external permissioned {
        withdrawApproval[withdrawer_][token_] -= amount_;
        emit DecreaseWithdrawApproval(withdrawer_, token_, withdrawApproval[withdrawer_][token_]);
    }

    /// @notice Withdraw from reserves for pre-approved withdrawers
    function withdrawReserves(address to_, ERC20 token_, uint256 amount_) external onlyWhileActive permissioned {
        require(withdrawApproval[msg.sender][token_] >= amount_, "TRSRY: Withdrawal not approved");
        withdrawApproval[msg.sender][token_] -= amount_;
        token_.transfer(to_, amount_);
        emit Withdrawal(msg.sender, to_, token_, amount_);
    }

    /// @notice Increase debt approval
    function increaseDebtorApproval(address debtor_, ERC20 token_, uint256 amount_) external permissioned {
        debtApproval[debtor_][token_] += amount_;
        emit IncreaseDebtorApproval(debtor_, token_, debtApproval[debtor_][token_]);
    }

    /// @notice Decrease debt approval
    function decreaseDebtorApproval(address debtor_, ERC20 token_, uint256 amount_) external permissioned {
        debtApproval[debtor_][token_] -= amount_;
        emit DecreaseDebtorApproval(debtor_, token_, debtApproval[debtor_][token_]);
    }

    /// @notice Allow an approved policy to incur debt
    function incurDebt(ERC20 token_, uint256 amount_) external onlyWhileActive permissioned {
        require(debtApproval[msg.sender][token_] >= amount_, "TRSRY: Debt not approved");
        totalDebt[token_] += amount_;
        reserveDebt[token_][msg.sender] += amount_;
        emit DebtIncurred(token_, msg.sender, amount_);
    }

    /// @notice Repay debt
    function repayDebt(address debtor_, ERC20 token_, uint256 amount_) external {
        require(reserveDebt[token_][debtor_] >= amount_, "TRSRY: No debt outstanding");
        reserveDebt[token_][debtor_] -= amount_;
        totalDebt[token_] -= amount_;
        emit DebtRepaid(token_, debtor_, amount_);
    }

    /// @notice Set debt in case of emergencies
    function setDebt(address debtor_, ERC20 token_, uint256 amount_) external onlyKernel {
        reserveDebt[token_][debtor_] = amount_;
        emit DebtSet(token_, debtor_, amount_);
    }

    /// @notice Get the current reserve balance
    function getReserveBalance(ERC20 token_) external view returns (uint256) {
        return token_.balanceOf(address(this)) + totalDebt[token_];
    }

    /// @notice Emergency shutdown of withdrawals and debt
    function deactivate() external onlyKernel {
        active = false;
    }

    /// @notice Re-activate after shutdown
    function activate() external onlyKernel {
        active = true;
    }
}
