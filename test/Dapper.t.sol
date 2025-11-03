// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Dapper} from "../src/Dapper.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../src/Vault.sol";

contract DapperTest is Test {
    Dapper public dapper;
    MockERC20 public depositToken;
    Vault public yieldVault;
    Vault public beneficiaryVault;

    address public deployer = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 public constant INTEREST_RATE_BPS = 500; // 5%
    uint256 public constant STAKE_AMOUNT = 1000e18;
    uint256 public constant LOCK_DURATION = 30 days;

    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy MockERC20 token
        depositToken = new MockERC20("Deposit Token", "DEP");
        
        // Deploy YieldVault separately
        yieldVault = new Vault(address(depositToken), "Yield Vault Token", "YIELD");
        
        // Deploy Dapper contract (which will deploy BeneficiaryVault)
        dapper = new Dapper(address(depositToken), INTEREST_RATE_BPS, address(yieldVault));
        
        // Get beneficiary vault address
        address beneficiaryVaultAddr = dapper.getBeneficiaryVaultAddress();
        beneficiaryVault = Vault(beneficiaryVaultAddr);
        
        vm.stopPrank();

        // Mint tokens to users
        depositToken.mint(user1, 10000e18);
        depositToken.mint(user2, 10000e18);
    }

    function test_Initialization() public view {
        assertEq(address(dapper.depositToken()), address(depositToken));
        assertEq(dapper.interestRateBps(), INTEREST_RATE_BPS);
        assertEq(dapper.deployer(), deployer);
        assertEq(address(dapper.getYieldVaultAddress()), address(yieldVault));
        assertEq(address(dapper.getBeneficiaryVaultAddress()), address(beneficiaryVault));
    }

    function test_Stake() public {
        vm.startPrank(user1);

        uint256 initialBalance = depositToken.balanceOf(user1);
        uint256 initialVaultAssets = yieldVault.totalAssets();
        
        // Calculate expected interest
        uint256 interestPaid = (STAKE_AMOUNT * LOCK_DURATION * INTEREST_RATE_BPS) / (10000 * 365 days);
        uint256 netAmount = STAKE_AMOUNT - interestPaid;

        // Approve and stake
        depositToken.approve(address(dapper), STAKE_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit Dapper.Staked(
            1, 
            user1, 
            STAKE_AMOUNT, 
            LOCK_DURATION, 
            block.timestamp + LOCK_DURATION, 
            interestPaid
        );
        
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        // Check NFT was minted
        assertEq(dapper.ownerOf(1), user1);
        
        // Check stake details
        (uint256 shares, uint256 amountStaked, uint256 unlockTimestamp) = dapper.stakeDetails(1);
        assertEq(shares, yieldVault.balanceOf(address(dapper)));
        assertEq(amountStaked, STAKE_AMOUNT);
        assertEq(unlockTimestamp, block.timestamp + LOCK_DURATION);

        // Check balances
        assertEq(depositToken.balanceOf(user1), initialBalance - netAmount);
        assertEq(yieldVault.totalAssets(), initialVaultAssets + netAmount);

        vm.stopPrank();
    }

    function test_StakeMultiple() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), type(uint256).max);
        
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);
        assertEq(dapper.ownerOf(1), user1);

        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);
        assertEq(dapper.ownerOf(2), user1);

        vm.stopPrank();

        vm.startPrank(user2);
        depositToken.approve(address(dapper), type(uint256).max);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);
        assertEq(dapper.ownerOf(3), user2);
        vm.stopPrank();
    }

    function test_UnstakeBeforeUnlockReverts() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), STAKE_AMOUNT);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        // Try to unstake before unlock
        vm.expectRevert("Stake has not expired");
        dapper.unstake(1);

        vm.stopPrank();
    }

    function test_UnstakeNotOwnerReverts() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), STAKE_AMOUNT);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        vm.stopPrank();

        // Try to unstake as different user
        vm.startPrank(user2);
        vm.warp(block.timestamp + LOCK_DURATION + 1);

        vm.expectRevert("You are not the owner of this stake");
        dapper.unstake(1);

        vm.stopPrank();
    }

    function test_Unstake() public {
        vm.startPrank(user1);

        uint256 initialBalance = depositToken.balanceOf(user1);
        
        depositToken.approve(address(dapper), STAKE_AMOUNT);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        dapper.stakeDetails(1);
        
        // Warp to after unlock
        vm.warp(block.timestamp + LOCK_DURATION + 1);

        depositToken.balanceOf(address(beneficiaryVault));
        
        vm.expectEmit(true, true, true, true);
        emit Dapper.Unstaked(1, user1, 0); // No yield initially
        
        dapper.unstake(1);

        // Check NFT was burned
        vm.expectRevert();
        dapper.ownerOf(1);

        // Check user received the staked amount back
        assertEq(depositToken.balanceOf(user1), initialBalance);
        
        // Check beneficiary vault balance (should have shares but no yield yet)
        assertGt(yieldVault.balanceOf(address(beneficiaryVault)), 0);

        vm.stopPrank();
    }

    function test_UnstakeWithYield() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), STAKE_AMOUNT);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        (uint256 shares, uint256 amountStaked,) = dapper.stakeDetails(1);
        
        // Simulate yield by minting tokens to the yield vault
        // This increases totalAssets without increasing shares, creating yield
        uint256 yieldAmount = 100e18; // 10% yield
        depositToken.mint(address(yieldVault), yieldAmount);

        // Warp to after unlock
        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 initialBeneficiaryBalance = depositToken.balanceOf(address(beneficiaryVault));
        uint256 initialUserBalance = depositToken.balanceOf(user1);

        // Calculate expected shares to redeem
        uint256 totalShares = yieldVault.totalSupply();
        uint256 totalAssets = yieldVault.totalAssets();
        
        // Shares needed to withdraw amountStaked
        uint256 sharesToWithdraw = (amountStaked * totalShares) / totalAssets;
        uint256 excessShares = shares - sharesToWithdraw;
        
        // Expected assets from excess shares (this goes to beneficiary)
        uint256 expectedFee = (excessShares * totalAssets) / totalShares;

        dapper.unstake(1);

        // User should receive exactly amountStaked
        assertEq(depositToken.balanceOf(user1), initialUserBalance);
        
        // Beneficiary vault should receive the excess shares value
        assertGt(depositToken.balanceOf(address(beneficiaryVault)), initialBeneficiaryBalance);
        
        // The beneficiary vault should have received the yield portion
        uint256 beneficiaryAssets = depositToken.balanceOf(address(beneficiaryVault));
        assertApproxEqRel(beneficiaryAssets, expectedFee, 0.01e18); // 1% tolerance for rounding

        vm.stopPrank();
    }

    function test_InterestCalculation() public {
        vm.startPrank(user1);

        uint256 amount = 1000e18;
        uint256 duration = 365 days;
        
        // Interest = (amount * duration * interestRateBps) / (10000 * 365 days)
        // For 1000 tokens, 365 days, 5%: (1000 * 365 * 500) / (10000 * 365) = 50 tokens
        uint256 expectedInterest = (amount * duration * INTEREST_RATE_BPS) / (10000 * 365 days);
        assertEq(expectedInterest, 50e18); // 5% of 1000 = 50

        depositToken.approve(address(dapper), amount);
        
        uint256 balanceBefore = depositToken.balanceOf(user1);
        
        vm.expectEmit(true, true, true, true);
        emit Dapper.Staked(1, user1, amount, duration, block.timestamp + duration, expectedInterest);
        
        dapper.stake(amount, duration);

        // User should have paid (amount - interest)
        uint256 balanceAfter = depositToken.balanceOf(user1);
        assertEq(balanceBefore - balanceAfter, amount - expectedInterest);

        vm.stopPrank();
    }

    function test_InterestRateBpsSet() public {
        vm.startPrank(deployer);

        uint256 newRate = 1000; // 10%
        
        vm.expectEmit(true, true, true, true);
        emit Dapper.InterestRateBpsSet(newRate);
        
        dapper.setInterestRateBps(newRate);
        
        assertEq(dapper.interestRateBps(), newRate);

        vm.stopPrank();
    }

    function test_InterestRateBpsSetNotDeployerReverts() public {
        vm.startPrank(user1);

        vm.expectRevert("Only deployer can call this function");
        dapper.setInterestRateBps(1000);

        vm.stopPrank();
    }

    function test_MultipleStakesWithYield() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), type(uint256).max);
        
        // First stake
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);
        (, uint256 amount1,) = dapper.stakeDetails(1);

        // Second stake
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);
        (, uint256 amount2,) = dapper.stakeDetails(2);

        // Generate yield
        uint256 yieldAmount = 200e18;
        depositToken.mint(address(yieldVault), yieldAmount);

        // Unlock both stakes
        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 userBalanceBefore = depositToken.balanceOf(user1);
        uint256 beneficiaryBalanceBefore = depositToken.balanceOf(address(beneficiaryVault));

        // Unstake first
        dapper.unstake(1);
        uint256 userBalanceAfterFirst = depositToken.balanceOf(user1);
        
        // Unstake second
        dapper.unstake(2);
        uint256 userBalanceAfterSecond = depositToken.balanceOf(user1);

        // Both users should have received their staked amounts
        assertEq(userBalanceAfterFirst - userBalanceBefore, amount1);
        assertEq(userBalanceAfterSecond - userBalanceAfterFirst, amount2);

        // Beneficiary should have received yield from both stakes
        assertGt(depositToken.balanceOf(address(beneficiaryVault)), beneficiaryBalanceBefore);

        vm.stopPrank();
    }

    function test_YieldSimulation() public {
        vm.startPrank(user1);

        depositToken.approve(address(dapper), STAKE_AMOUNT);
        dapper.stake(STAKE_AMOUNT, LOCK_DURATION);

        // Check initial vault state
        uint256 initialVaultAssets = yieldVault.totalAssets();
        uint256 initialVaultShares = yieldVault.totalSupply();
        
        // Simulate yield by minting directly to vault
        uint256 yieldAmount = 50e18;
        depositToken.mint(address(yieldVault), yieldAmount);

        // Vault assets increased but shares stayed the same
        assertEq(yieldVault.totalAssets(), initialVaultAssets + yieldAmount);
        assertEq(yieldVault.totalSupply(), initialVaultShares);
        
        // Exchange rate increased (assets per share)
        uint256 assetsPerShareBefore = (initialVaultAssets * 1e18) / initialVaultShares;
        uint256 assetsPerShareAfter = (yieldVault.totalAssets() * 1e18) / yieldVault.totalSupply();
        assertGt(assetsPerShareAfter, assetsPerShareBefore);

        vm.stopPrank();
    }
}

