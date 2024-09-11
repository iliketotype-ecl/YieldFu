// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "./DEBASE.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../Kernel.sol";
import "./MINTR.sol";

contract BOND is Module, ReentrancyGuard, Pausable {
    // =========  EVENTS ========= //
    event BondCreated(address indexed user, uint256 amount, uint256 payout);
    event BondClaimed(address indexed user, uint256 payout);
    event DiscountChanged(bool isEth, uint256 newDiscount);
    event BondingPaused(address indexed by);
    event BondingUnpaused(address indexed by);
    event MaxBondSizeChanged(uint256 newSize);
    event BondCooldownChanged(uint256 newCooldown);
    event TreasuryChanged(address newTreasury);

    // ========= ERRORS ========= //
    error BOND_ZeroAmount();
    error BOND_NotMatured();
    error BOND_AlreadyClaimed();
    error BOND_CooldownNotMet();
    error BOND_MaxBondSizeExceeded();
    error BOND_InvalidDiscount();
    error BOND_InvalidTreasury();

    // =========  STATE ========= //
    YieldFuToken public token;
    address public treasury;
    MINTR public mintrModule;
    uint256 public ethDiscount = 150; // 15% represented as 150
    uint256 public partnerDiscount = 250; // 25% represented as 250
    uint256 public constant BOND_MATURITY = 3 days;
    uint256 public maxBondSize;
    uint256 public bondCooldown;

    struct BondInfo {
        uint256 payout;
        uint256 maturity;
        bool claimed;
    }

    mapping(address => BondInfo) public bonds;
    mapping(address => uint256) public lastBondTime;

    constructor(
        Kernel kernel_,
        address token_,
        address treasury_,
        MINTR mintrModule_,
        uint256 maxBondSize_,
        uint256 bondCooldown_
    ) Module(kernel_) {
        token = YieldFuToken(token_);
        treasury = treasury_;
        mintrModule = mintrModule_;
        maxBondSize = maxBondSize_;
        bondCooldown = bondCooldown_;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("BONDS");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 1); // Updated to v1.1
    }

    function INIT() external override onlyKernel {
        // Initialization logic, if any
    }

    function bondEth() external payable nonReentrant permissioned whenNotPaused {
        if (msg.value == 0) revert BOND_ZeroAmount();
        if (msg.value > maxBondSize) revert BOND_MaxBondSizeExceeded();
        if (block.timestamp < lastBondTime[msg.sender] + bondCooldown) revert BOND_CooldownNotMet();

        uint256 payout = calculatePayout(msg.value, ethDiscount);
        _createBond(payout);
        payable(treasury).transfer(msg.value);
        lastBondTime[msg.sender] = block.timestamp;
    }

    function bondPartnerToken(address tokenAddress, uint256 amount) external nonReentrant permissioned whenNotPaused {
        if (amount == 0) revert BOND_ZeroAmount();
        if (amount > maxBondSize) revert BOND_MaxBondSizeExceeded();
        if (block.timestamp < lastBondTime[msg.sender] + bondCooldown) revert BOND_CooldownNotMet();

        IERC20 partnerToken = IERC20(tokenAddress);
        uint256 payout = calculatePayout(amount, partnerDiscount);
        _createBond(payout);
        partnerToken.transferFrom(msg.sender, treasury, amount);
        lastBondTime[msg.sender] = block.timestamp;
    }

     function claimBond() external nonReentrant permissioned whenNotPaused {
        BondInfo storage bond = bonds[msg.sender];
        if (block.timestamp < bond.maturity) revert BOND_NotMatured();
        if (bond.claimed) revert BOND_AlreadyClaimed();

        bond.claimed = true;
        mintrModule.mint(msg.sender, bond.payout);
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
        if (newDiscount > 500) revert BOND_InvalidDiscount(); // Max 50% discount
        if (isEth) {
            ethDiscount = newDiscount;
        } else {
            partnerDiscount = newDiscount;
        }
        emit DiscountChanged(isEth, newDiscount);
    }

    function pauseBonding() external permissioned {
        _pause();
        emit BondingPaused(msg.sender);
    }

    function unpauseBonding() external permissioned {
        _unpause();
        emit BondingUnpaused(msg.sender);
    }

    function setMaxBondSize(uint256 newSize) external permissioned {
        maxBondSize = newSize;
        emit MaxBondSizeChanged(newSize);
    }

    function setBondCooldown(uint256 newCooldown) external permissioned {
        bondCooldown = newCooldown;
        emit BondCooldownChanged(newCooldown);
    }

    function setTreasury(address newTreasury) external permissioned {
        if (newTreasury == address(0)) revert BOND_InvalidTreasury();
        treasury = newTreasury;
        emit TreasuryChanged(newTreasury);
    }

    // View functions
    function getBondInfo(address user) external view returns (uint256 payout, uint256 maturity, bool claimed) {
        BondInfo memory bond = bonds[user];
        return (bond.payout, bond.maturity, bond.claimed);
    }

    function getLastBondTime(address user) external view returns (uint256) {
        return lastBondTime[user];
    }
}