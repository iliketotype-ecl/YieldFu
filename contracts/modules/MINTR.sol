// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../Kernel.sol";
import "../YieldFu.sol";

contract MINTR is Module, Pausable {
    // =========  EVENTS ========= //
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event MintCapChanged(uint256 newDailyMintCap);
    event MintLimitChanged(address indexed policy, uint256 newLimit);

    // ========= ERRORS ========= //
    error MINTR_Unauthorized();
    error MINTR_DailyCapExceeded();
    error MINTR_PolicyLimitExceeded();
    error MINTR_InvalidMintCap();
    error MINTR_InvalidMintLimit();

    // =========  STATE ========= //
    YieldFuToken public immutable yieldFu;
    uint256 public dailyMintCap;
    uint256 public mintedToday;
    uint256 public lastMintDay;

    mapping(address => uint256) public policyLimits;
    mapping(address => uint256) public policyMinted;

    constructor(Kernel kernel_, YieldFuToken yieldFu_, uint256 initialDailyMintCap_) Module(kernel_) {
        yieldFu = yieldFu_;
        dailyMintCap = initialDailyMintCap_;
        lastMintDay = block.timestamp / 1 days;
    }

    function KEYCODE() public pure override returns (Keycode) {
        console.log("MINTR: Returning Keycode MINTR as bytes5");
        return toKeycode("MINTR");
    }



    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 3); // v1.3
    }

    // ================= Mint/Burn Functions =================== //
    function mint(address to_, uint256 amount_) external permissioned {
        _updateDailyMint(); // Reset daily limits if it's a new day
        _checkMintLimits(msg.sender, amount_); // Ensure minting stays within limits

        yieldFu.mint(to_, amount_); // Proceed with minting tokens
        policyMinted[msg.sender] += amount_; // Update policy minted amount
        mintedToday += amount_; // Update total minted today

        emit Minted(to_, amount_);
    }

    function burn(address from, uint256 amount) external permissioned whenNotPaused {
        yieldFu.burnFrom(from, amount);
        emit Burned(from, amount);
    }

    // ================= Policy Limit Management =================== //
    function setPolicyLimit(address policy, uint256 limit) external permissioned {
        if (limit == 0) revert MINTR_InvalidMintLimit();
        policyLimits[policy] = limit;
        emit MintLimitChanged(policy, limit);
    }

    function changeDailyMintCap(uint256 newCap) external permissioned {
        if (newCap == 0) revert MINTR_InvalidMintCap();
        dailyMintCap = newCap;
        emit MintCapChanged(newCap);
    }

    // ================= Internal Utility Functions =================== //
    function _updateDailyMint() internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastMintDay) {
            mintedToday = 0; // Reset daily mint
            lastMintDay = currentDay;
        }
    }

    function _checkMintLimits(address policy, uint256 amount) internal view {
        if (mintedToday + amount > dailyMintCap) {
            revert MINTR_DailyCapExceeded();
        }
        if (policyMinted[policy] + amount > policyLimits[policy]) {
            revert MINTR_PolicyLimitExceeded();
        }
    }

    // ================= View Functions =================== //
    function getPolicyInfo(address policy) external view returns (uint256 mintLimit, uint256 mintedAmount) {
        return (policyLimits[policy], policyMinted[policy]);
    }

    function getDailyMintInfo() external view returns (uint256 cap, uint256 minted, uint256 remaining) {
        return (dailyMintCap, mintedToday, dailyMintCap - mintedToday);
    }
}
