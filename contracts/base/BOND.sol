// BOND Contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BOND is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    uint256 public constant BOND_MATURITY = 3 days;
    uint256 public ethUsdtDiscount = 1500; // 15% discount (in basis points)
    uint256 public partnerTokenDiscount = 2500; // 25% discount (in basis points)
    
    error DiscountTooHigh(uint256 discount);

    IERC20 public immutable debaseToken;
    IERC20 public immutable partnerToken;

    struct Bond {
        uint256 payout;
        uint256 maturity;
    }

    mapping(address => Bond) public bonds;

    event BondCreated(address indexed user, uint256 deposit, uint256 payout, bool isPartnerToken);
    event BondRedeemed(address indexed user, uint256 payout);
    event DiscountUpdated(bool isPartnerToken, uint256 newDiscount);

    constructor(address _debaseToken, address _partnerToken) {
        require(_debaseToken != address(0), "Invalid DEBASE token address");
        require(_partnerToken != address(0), "Invalid partner token address");
        debaseToken = IERC20(_debaseToken);
        partnerToken = IERC20(_partnerToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
    }

    function createBond(address user, uint256 deposit, bool isPartnerToken) 
        external 
        onlyRole(CONTROLLER_ROLE) 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        require(deposit > 0, "Deposit must be greater than zero");
        require(bonds[user].payout == 0, "User already has an active bond");

        uint256 discount = isPartnerToken ? partnerTokenDiscount : ethUsdtDiscount;
        uint256 payout = deposit + (deposit * discount / 10000);
        
        bonds[user] = Bond({
            payout: payout,
            maturity: block.timestamp + BOND_MATURITY
        });

        emit BondCreated(user, deposit, payout, isPartnerToken);
        return payout;
    }

    function redeemBond(address user) 
        external 
        onlyRole(CONTROLLER_ROLE) 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        Bond memory bond = bonds[user];
        require(bond.payout > 0, "No bond found");
        require(block.timestamp >= bond.maturity, "Bond not yet matured");

        uint256 payout = bond.payout;
        delete bonds[user];

        emit BondRedeemed(user, payout);
        return payout;
    }

    function setDiscount(bool isPartnerToken, uint256 newDiscount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (newDiscount > 5000) {
            revert DiscountTooHigh(newDiscount);
        }
        if (isPartnerToken) {
            partnerTokenDiscount = newDiscount;
        } else {
            ethUsdtDiscount = newDiscount;
        }
        emit DiscountUpdated(isPartnerToken, newDiscount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}