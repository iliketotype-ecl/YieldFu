// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "./DEBASE.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../Kernel.sol";

contract BOND is Module, ReentrancyGuard {
    // =========  EVENTS ========= //
    event BondCreated(address indexed user, uint256 amount, uint256 payout);
    event BondClaimed(address indexed user, uint256 payout);
    event DiscountChanged(uint256 newDiscount);

    // ========= ERRORS ========= //
    error BOND_ZeroAmount();
    error BOND_NotMatured();
    error BOND_AlreadyClaimed();

    // =========  STATE ========= //
    DEBASE public token;
    address public treasury;
    uint256 public ethDiscount = 150; // 15% represented as 150
    uint256 public partnerDiscount = 250; // 25% represented as 250
    uint256 public constant BOND_MATURITY = 3 days;

    struct BondInfo {
        uint256 payout;
        uint256 maturity;
        bool claimed;
    }

    mapping(address => BondInfo) public bonds;

    constructor(Kernel kernel_, address token_, address treasury_) Module(kernel_) {
        token = DEBASE(token_);
        treasury = treasury_;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("BONDS");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0); // v1.0
    }

    function INIT() external override onlyKernel {
        // Initialization logic, if any
    }

    function bondEth() external payable nonReentrant permissioned {
        if (msg.value == 0) revert BOND_ZeroAmount();
        uint256 payout = calculatePayout(msg.value, ethDiscount);
        _createBond(payout);
        payable(treasury).transfer(msg.value);
    }

    function bondPartnerToken(address tokenAddress, uint256 amount) external nonReentrant permissioned {
        if (amount == 0) revert BOND_ZeroAmount();
        IERC20 partnerToken = IERC20(tokenAddress);
        uint256 payout = calculatePayout(amount, partnerDiscount);
        _createBond(payout);
        partnerToken.transferFrom(msg.sender, treasury, amount);
    }

    function claimBond() external nonReentrant permissioned {
        BondInfo storage bond = bonds[msg.sender];
        if (block.timestamp < bond.maturity) revert BOND_NotMatured();
        if (bond.claimed) revert BOND_AlreadyClaimed();

        bond.claimed = true;
        token.transfer(msg.sender, bond.payout);
        emit BondClaimed(msg.sender, bond.payout);
    }

    function _createBond(uint256 payout) internal {
        bonds[msg.sender] = BondInfo({
            payout: payout,
            maturity: block.timestamp + BOND_MATURITY,
            claimed: false
        });
        emit BondCreated(msg.sender, msg.value, payout);
    }

    function calculatePayout(uint256 amount, uint256 discount) public pure returns (uint256) {
        return amount + (amount * discount / 1000);
    }

    function changeDiscount(bool isEth, uint256 newDiscount) external permissioned {
        if (isEth) {
            ethDiscount = newDiscount;
        } else {
            partnerDiscount = newDiscount;
        }
        emit DiscountChanged(newDiscount);
    }
}