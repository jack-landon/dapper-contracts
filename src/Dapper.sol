// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Vault} from "./Vault.sol";

contract Dapper is ERC721, ERC721Burnable {
    using SafeERC20 for IERC20;

    uint256 stakeId;
    address public deployer;
    address public immutable depositToken;
    uint256 public interestRateBps;
    address public yieldVaultAddress;
    Vault public beneficiaryVault;

    mapping(uint256 => Stake) public stakeDetails;

    struct Stake {
        uint256 shares;
        uint256 amountStaked;
        uint256 unlockTimestamp;
    }

    event Initialized(address indexed depositToken, uint256 interestRateBps, address yieldVault, address beneficiaryVault);
    event Staked(uint256 indexed stakeId, address indexed user, uint256 amountStaked, uint256 lockDuration, uint256 unlockTimestamp, uint256 interestPaid);
    event Unstaked(uint256 indexed stakeId, address indexed receiver, uint256 feeGenerated);
    event InterestRateBpsSet(uint256 interestRateBps);
    
    constructor(address _depositToken, uint256 _interestRateBps, address _yieldVaultAddress) ERC721("Dapper Stake", "sDAP") {
        depositToken = _depositToken;
        interestRateBps = _interestRateBps;
        stakeId = 0;
        deployer = msg.sender;
        yieldVaultAddress = _yieldVaultAddress;
        beneficiaryVault = new Vault(_depositToken, "Dapper Beneficiary Vault Token", "bDAP");

        emit Initialized(depositToken, _interestRateBps, _yieldVaultAddress, address(beneficiaryVault));
    }
    
    function stake(uint256 amount, uint256 lockDuration) external {
        // 1. Calculate the interest to be paid
        uint256 interestPaid = Math.mulDiv(amount, lockDuration * interestRateBps, 10000 * 365 days);

        require(interestPaid > 0, "Interest paid is 0");
        require(amount > interestPaid, "Deposited amount is less than interest");

        uint256 netAmount = amount - interestPaid;

        // 2. Get the funds from the depositor
        IERC20(depositToken).safeTransferFrom(msg.sender, address(this), netAmount);

        // 3. Approve vault to spend tokens, then deposit the funds into the vault
        IERC20(depositToken).safeIncreaseAllowance(yieldVaultAddress, netAmount);
        uint256 shares = Vault(yieldVaultAddress).deposit(netAmount, address(this));

        // 4. Create the NFT
        uint256 id = ++stakeId;
        uint256 unlockTimestamp = block.timestamp + lockDuration;
        Stake memory newStake = Stake({
            shares: shares,
            amountStaked: amount,
            unlockTimestamp: unlockTimestamp
        });
        stakeDetails[id] = newStake;

        // 5. Mint the NFT to the user
        _safeMint(msg.sender, id);

        emit Staked(id, msg.sender, amount, lockDuration, unlockTimestamp, interestPaid);
    }

    function unstake(uint256 _stakeId) external {
        // 1. Get the stake details
        Stake memory targetStake = stakeDetails[_stakeId];

        // 2. Check if the stake is able to be unlocked
        require(targetStake.unlockTimestamp <= block.timestamp, "Stake has not expired");
        require(ownerOf(_stakeId) == msg.sender, "You are not the owner of this stake");

        // 3. Burn the NFT
        _burn(_stakeId);

        // 4. Redeem all shares to get the total assets
        uint256 totalAssets = Vault(yieldVaultAddress).redeem(targetStake.shares, address(this), address(this));

        // 5. Send the locked amount (or all assets if vault lost value) to the user
        uint256 amountToUser = totalAssets > targetStake.amountStaked ? targetStake.amountStaked : totalAssets;
        IERC20(depositToken).safeTransfer(msg.sender, amountToUser);

        // 6. Send any excess (yield) to the beneficiary vault
        uint256 feeGenerated = 0;
        if (totalAssets > targetStake.amountStaked) {
            feeGenerated = totalAssets - targetStake.amountStaked;
            IERC20(depositToken).safeTransfer(address(beneficiaryVault), feeGenerated);
        }

        emit Unstaked(_stakeId, msg.sender, feeGenerated);
    }

    function getYieldVaultAddress() external view returns (address) {
        return yieldVaultAddress;
    }

    function getBeneficiaryVaultAddress() external view returns (address) {
        return address(beneficiaryVault);
    }

    function setInterestRateBps(uint256 _interestRateBps) external {
        require(msg.sender == deployer, "Only deployer can call this function");
        interestRateBps = _interestRateBps;
        emit InterestRateBpsSet(_interestRateBps);
    }
}