// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "../Kernel.sol";
import "../YieldFu.sol";
import "hardhat/console.sol"; // Keep this for logging

contract MINTR is Module, Pausable {
    // =========  EVENTS ========= //
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event MintCapChanged(uint256 newDailyMintCap);
    event MintLimitChanged(address indexed minter, uint256 newLimit);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event MinterCheck(address indexed minter, bool isMinter);
    event MintAttempt(address indexed minter, address indexed to, uint256 amount, bool success);
    event MintFunctionCalled(address caller, address to, uint256 amount);
    event MinterAuthorizationAttempt(address caller, bool isRegisteredMinter);

    // ========= ERRORS ========= //
    error MINTR_Unauthorized();
    error MINTR_DailyCapExceeded();
    error MINTR_MinterLimitExceeded();
    error MINTR_InvalidMintCap();
    error MINTR_InvalidMintLimit();
    error MINTR_AlreadyMinter();
    error MINTR_NotMinter();

    // =========  STATE ========= //
    YieldFuToken public yieldFu;
    uint256 public dailyMintCap;
    uint256 public mintedToday;
    uint256 public lastMintDay;

    mapping(address => bool) public isMinter;
    mapping(address => uint256) public minterLimits;
    mapping(address => uint256) public minterMinted;

    constructor(Kernel kernel_, YieldFuToken yieldFu_, uint256 initialDailyMintCap_) Module(kernel_) {
        yieldFu = yieldFu_;
        dailyMintCap = initialDailyMintCap_;
        lastMintDay = block.timestamp / 1 days;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("MINTR");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 2); // v1.2
    }


    function _checkMintLimits(uint256 amount) internal view {
        if (mintedToday + amount > dailyMintCap) revert MINTR_DailyCapExceeded();
        if (minterMinted[msg.sender] + amount > minterLimits[msg.sender]) revert MINTR_MinterLimitExceeded();
    }

    modifier onlyMinter() {
            bool isAuthorized = isMinter[msg.sender];
            console.log("MINTR: Checking minter authorization for", msg.sender);
            console.log("MINTR: Is minter authorized?", isAuthorized);
            emit MinterAuthorizationAttempt(msg.sender, isAuthorized);
            emit MinterCheck(msg.sender, isAuthorized);
            if (!kernel.modulePermissions(KEYCODE(), Policy(msg.sender), this.mint.selector)) {
                revert MINTR_Unauthorized();
            }
            _;
        }

    function mint(address minter, address to, uint256 amount) external whenNotPaused {
        console.log("MINTR: Mint function called by", msg.sender);
        console.log("MINTR: Minter address:", minter);
        console.log("MINTR: Minting", amount, "tokens for", to);
        console.log("MINTR: Is caller authorized?", isMinter[msg.sender]);

        if (!isMinter[msg.sender]) {
            console.log("MINTR: Caller is not authorized");
            revert MINTR_Unauthorized();
        }

        _updateDailyMint();
        _checkMintLimits(msg.sender, amount);

        // Direct call to mint function without try/catch
        yieldFu.mint(to, amount);
        console.log("MINTR: Minting successful");

        mintedToday += amount;
        minterMinted[msg.sender] += amount;
        emit Minted(to, amount);
        emit MintAttempt(msg.sender, to, amount, true); // Indicate success
    }


    function _checkMintLimits(address minter, uint256 amount) internal view {
        if (mintedToday + amount > dailyMintCap) revert MINTR_DailyCapExceeded();
        if (minterMinted[minter] + amount > minterLimits[minter]) revert MINTR_MinterLimitExceeded();
    }


    function burn(address from, uint256 amount) external whenNotPaused permissioned {
        yieldFu.burnFrom(from, amount);
        emit Burned(from, amount);
    }

    function addMinter(address _minter, uint256 _limit) external permissioned {
        if (isMinter[_minter]) revert MINTR_AlreadyMinter();
        isMinter[_minter] = true;  
        minterLimits[_minter] = _limit; 
        emit MinterAdded(_minter);
        emit MintLimitChanged(_minter, _limit);
    }

    function removeMinter(address minter) external permissioned {
        if (!isMinter[minter]) revert MINTR_NotMinter();
        isMinter[minter] = false;
        delete minterLimits[minter];
        delete minterMinted[minter];
        emit MinterRemoved(minter);
    }

    function changeMintLimit(address minter, uint256 newLimit) external permissioned {
        if (!isMinter[minter]) revert MINTR_NotMinter();
        if (newLimit == 0) revert MINTR_InvalidMintLimit();
        minterLimits[minter] = newLimit;
        emit MintLimitChanged(minter, newLimit);
    }

    function changeDailyMintCap(uint256 newCap) external permissioned {
        if (newCap == 0) revert MINTR_InvalidMintCap();
        dailyMintCap = newCap;
        emit MintCapChanged(newCap);
    }

    function pauseMinting() external permissioned {
        _pause();
    }

    function unpauseMinting() external permissioned {
        _unpause();
    }

    function _updateDailyMint() internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastMintDay) {
            mintedToday = 0;
            lastMintDay = currentDay;
        }
    }

    // View functions
    function getMinterInfo(address minter) external view returns (
        bool isActive,
        uint256 mintLimit,
        uint256 mintedAmount
    ) {
        return (isMinter[minter], minterLimits[minter], minterMinted[minter]);
    }

    function getDailyMintInfo() external view returns (
        uint256 cap,
        uint256 minted,
        uint256 remaining
    ) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 currentMinted = currentDay > lastMintDay ? 0 : mintedToday;
        return (dailyMintCap, currentMinted, dailyMintCap - currentMinted);
    }
}