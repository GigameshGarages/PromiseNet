// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import { IERC20, IERC721, ILendingPool, IProtocolDataProvider, IStableDebtToken } from './Interfaces.sol';
import { SafeERC20, SafeMath } from './Libraries.sol';

/**
 * This is a proof of concept starter contract, showing how uncollaterised loans are possible
 * using Aave v2 credit delegation.
 * This example supports stable interest rate borrows.
 * It is not production ready (!). User permissions and user accounting of loans should be implemented.
 * See @dev comments
 */
 
contract MyV2CreditDelegation {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    
    ILendingPool constant lendingPool = ILendingPool(address(0x9FE532197ad76c5a68961439604C037EB79681F0)); // Kovan
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(address(0x744C1aaA95232EeF8A9994C4E0b3a89659D9AB79)); // Kovan
    
    address owner;

    struct Term {
        uint256 limit; // Borrowing limit in wei
        uint256 rateMultiplier;  // Interest rate on top of Aave set rate
    }

    struct Loan {
        uint256 rateMultiplier;
        bool active;
        uint256 principalBalance;
    }

    // Track balances by asset address
    mapping (address => mapping (address => uint256)) public balances;

    // Map NFT addresses to limits
    mapping ( address => Term ) public terms;

    mapping ( address => mapping (uint256 => bool)) public burnedApprovals;

    // Track addresses with active loans. Same address cannot have multiple lines open per asset with different terms
    mapping ( address => mapping (address => Loan )) public loans;

    constructor () public {
        owner = msg.sender;
        terms[0x0000000000000000000000000000000000000001] = Term({limit: 1 ether, rateMultiplier: 5}); //Placeholder - limit arg should be an NFT address
        terms[0x0000000000000000000000000000000000000002] = Term({limit: 5 ether, rateMultiplier: 3}); // Placeholder - limit arg should be an NFT address
    }

    /**
     * Deposits collateral into the Aave, to enable credit delegation
     * This would be called by the delegator.
     * @param asset The asset to be deposited as collateral
     * @param amount The amount to be deposited as collateral
     *  User must have approved this contract
     * 
     */
    function depositCollateral(address asset, uint256 amount) public {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        // aTokens go to this contract
        lendingPool.deposit(asset, amount, address(this), 0);
        // Track how much collateral the investor has supplied
        balances[asset][msg.sender] += amount;
        // Track how much total collateral of this asset type has been supplied
        balances[asset][address(this)] += amount;
    }

    /**
     * Checks if sender is approved, and if so opens a credit delegation line
     * @param approvalNFT The NFT address representing the creditworthiness
     * @param tokenId The NFT ID of the approval being used
     * @param asset The asset they are allowed to borrow
     * 
     * Allows a borrower holding a valid NFT to borrow at the rate set in the constructor
     */
    function requestCredit(address approvalNFT, uint256 tokenId, address asset) public {
        require(IERC721(approvalNFT).ownerOf(tokenId) == msg.sender);
        burnedApprovals[approvalNFT][tokenId] = true;

        (, address stableDebtTokenAddress,) = dataProvider.getReserveTokensAddresses(asset);
        IStableDebtToken(stableDebtTokenAddress).approveDelegation(msg.sender, terms[approvalNFT].limit);

        // Note that we are assuming the borrower withdraws the full amount
        loans[stableDebtTokenAddress][msg.sender] = Loan({rateMultiplier: terms[approvalNFT].rateMultiplier, active: true, principalBalance: terms[approvalNFT].limit});
        // After this step the borrower can call borrow with this contract as the onBehalfOf
    }
    
    /**
     * Repay an uncollaterised loan
     * @param amount The amount to repay
     * @param asset The asset to be repaid
     * 
     * User calling this function must have approved this contract with an allowance to transfer the tokens
     */
    function repayBorrower(uint256 amount, address asset) public {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(lendingPool), amount);

        // Calculate the additional interest margin and extract that from the repayment amount
        (, address stableDebtTokenAddress,) = dataProvider.getReserveTokensAddresses(asset);
        uint256 principalBalance =  IStableDebtToken(stableDebtTokenAddress).principalBalanceOf(msg.sender);
        uint256 baseBalance =  IStableDebtToken(stableDebtTokenAddress).balanceOf(msg.sender);

        require(principalBalance == loans[stableDebtTokenAddress][msg.sender].principalBalance);

        // This will throw if accounting gets corrupted and lending pool balance is lower than principal balance
        uint256 baseInterest = baseBalance.sub(loans[stableDebtTokenAddress][msg.sender].principalBalance);

        uint256 premiumInterest = baseInterest.mul(loans[stableDebtTokenAddress][msg.sender].rateMultiplier);

        // Extract premium interest and distribute to pool
        uint256 repaymentAmount = amount.sub(premiumInterest);

        // The remaining amount stays in this contract gets deposited into the lending pool
        IERC20(asset).safeApprove(address(lendingPool), premiumInterest);
        // aTokens go to this contract
        lendingPool.deposit(asset, premiumInterest, address(this), 0);


        // Repaying has to be done at the aave rate
        // Repay uses the delegator's address for onBehalfOf
        lendingPool.repay(asset, repaymentAmount, 1, address(this));
        uint256 newPrincipalBalance =  IStableDebtToken(stableDebtTokenAddress).principalBalanceOf(msg.sender);
        loans[stableDebtTokenAddress][msg.sender].principalBalance = newPrincipalBalance;
    }

    /**
     * Check balance of the borrower
     * @param account The address of the borrower
     * @param asset The asset to be repaid
     * 
     */
    function balanceOf(address account, address asset) public view returns (uint256) {
        // Calculate the additional interest margin and extract that from the repayment amount
        (, address stableDebtTokenAddress,) = dataProvider.getReserveTokensAddresses(asset);
        uint256 principalBalance =  IStableDebtToken(stableDebtTokenAddress).principalBalanceOf(account);
        uint256 baseBalance =  IStableDebtToken(stableDebtTokenAddress).balanceOf(account);

        require(principalBalance == loans[stableDebtTokenAddress][account].principalBalance);

        // This will throw if accounting gets corrupted and lending pool balance is lower than principal balance
        uint256 baseInterest = baseBalance.sub(loans[stableDebtTokenAddress][account].principalBalance);

        uint256 premiumInterest = baseInterest.mul(loans[stableDebtTokenAddress][account].rateMultiplier);

        uint256 balance = baseBalance.add(premiumInterest);

        return balance;
    }


    /**
     * Withdraw all of a collateral as the underlying asset, if no outstanding loans delegated
     * @param asset The underlying asset to withdraw
     * 
     * Add permissions to this call, e.g. only the owner should be able to withdraw the collateral!
     */
    function withdrawCollateral(address asset) public {
        (address aTokenAddress,,) = dataProvider.getReserveTokensAddresses(asset);
        uint256 assetBalance = IERC20(aTokenAddress).balanceOf(address(this));
        uint256 senderCollateral = balances[asset][msg.sender];
        uint256 totalCollateral = balances[asset][address(this)];
        // Get the ratio of the collateral to evenly distribute rewards
        uint256 senderBalanceRatio = senderCollateral.div(totalCollateral);
        uint256 senderBalance = assetBalance.mul(senderBalanceRatio);
        balances[asset][msg.sender] -= senderCollateral;
        balances[asset][address(this)] -= senderCollateral;
        lendingPool.withdraw(asset, senderBalance, msg.sender);
    }
}
