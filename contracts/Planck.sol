pragma solidity 0.5.10;

/**
 * LIBRARIES
 */

import "./DSMath.sol";


/**
 * MAIN CONTRACT
 */

contract Planck is DSMath {

	/**
	 * STATE
	 */

	bool public reentracyGuard;
    
	uint256 public constant FEE = 3 * 10**15; //0.3%
	uint256 public shareSupply;

	mapping (address => uint256) public providerShares;
	mapping (address => uint256) public borrowerDebt;


	/**
	 * MODIFIERS
	 */

	//mutex to lock down functions during active loan
	modifier borrowLock() { 
		require (!reentracyGuard, "functions locked during active loan"); 
		_; 
	}


	/**
	 * EVENTS
	 */
	
	event LiquidityAdded(
		address indexed provider,
		uint256 ethAdded,
		uint256 sharesMinted
	);
	
	event LiquidityRemoved(
		address indexed provider,
		uint256 ethRemoved,
		uint256 sharesBurned
	);

	event LoanCompleted(
		address indexed borrower,
		uint256 debtRepayed
	);

	event LoanRepayed(
		address indexed borrower,
		address indexed payee,
		uint256 debtRepayed
	);

	/**
	 * USER FUNCTIONS
	 */
	
	//add ether liquidity and receive newly minted shares
	function provideLiquidity() external payable borrowLock {
		require(msg.value > 1 finney, "non-dust value required");
		//new liquidity as a percentage of total liquidity
		uint256 liquidityProportion = liquidityAsPercentage(msg.value); 
		//new shares minted to the same ratio
		uint256 sharesMinted = sharesAfterDeposit(liquidityProportion);
		//share balances updated in storage
		providerShares[msg.sender] = add(providerShares[msg.sender], sharesMinted);
		shareSupply = add(shareSupply, sharesMinted);

		emit LiquidityAdded(msg.sender, msg.value, sharesMinted);
	}

	//withdraw a portion of liquidtiy by burning shares owned
	function withdrawLiquidity(uint256 _shareAmount) external borrowLock {
		require (_shareAmount > 0, "non-zero value required");
		require (_shareAmount <= providerShares[msg.sender], "insufficient user balance"); 
		require (_shareAmount <= shareSupply, "insufficient global supply"); 

		//percentage and value of shares calcuated
		uint256 shareProportion = sharesAsPercentage(_shareAmount);
		uint256 shareValue = shareValue(shareProportion);
		//share balances updated in storage
		providerShares[msg.sender] = sub(providerShares[msg.sender], _shareAmount);
		shareSupply = sub(shareSupply, _shareAmount);
		//ether returned to user
		msg.sender.transfer(shareValue);

		emit LiquidityRemoved(msg.sender, shareValue, _shareAmount);
	}

	//issue a new loan
	function borrow(uint256 _ethAmount) external borrowLock {
		require (_ethAmount >= 1 finney, "non-dust value required");
		require (_ethAmount <= address(this).balance, "insufficient global liquidity"); 
		//@dev this should really be unreachable given the modifier
		require (borrowerDebt[msg.sender] == 0, "active loan in progress");
		//current balance recored and debt calculated
		uint256 initialLiquidity = address(this).balance;
		uint256 interest = calculateInterest(_ethAmount);
		uint256 outstandingDebt = add(_ethAmount, interest);
		//global mutex activated, pauding all functions except repayDebt()	
		reentracyGuard = true;
		//debt recoreded in storage (but gas will be partially refunded when it's zeroed out)
		borrowerDebt[msg.sender] = outstandingDebt;
		//requested funds sent to user via raw call with empty data
		//additional gas withheld to ensure the completion of this function
		//data is ignored
		bool result;
		(result, ) = msg.sender.call.gas(gasleft() - 10000).value(_ethAmount)(""); 
		//borrower can now execute actions triggered by a fallback function in their contract
		//they need to call repayDebt() and return the funds before this function continues
		require (result, "the call must return true");
		//will revert full tx if loan is not repaid
		require (address(this).balance >= add(initialLiquidity, interest), 
			"funds must be returned plus interest"
		);	
		// prevents mutex being locked via ether forced into contract rather than via repayDebt() 
		require (borrowerDebt[msg.sender] == 0, "borrower debt must be repaid in full"); 
		//mutex disabled
		reentracyGuard = false; 

		emit LoanCompleted(msg.sender, outstandingDebt);
	}

	//debt can be repaid from another address than the original borrower
	function repayDebt(address _borrower) public payable {
		require (reentracyGuard == true, "can only repay active loans");
		require (borrowerDebt[_borrower] != 0, "must repay outstanding debt");
		require (msg.value == borrowerDebt[_borrower], "debt must be repaid in full");

		uint256 outstandingDebt = borrowerDebt[_borrower];
		borrowerDebt[_borrower] = 0;

		emit LoanRepayed(_borrower, msg.sender, outstandingDebt);
	}

	//auto repay debt from msg.sender
	function() external payable {
		//shortcut for raw calls to repay debt
		repayDebt(msg.sender);
	}


	/**
	 * VIEW FUNCTIONS
	 */

	function sharesAsPercentage(uint256 _shareAmount) view public returns(
		uint256 _sharePercentage
	) {
		_sharePercentage = wdiv(_shareAmount, shareSupply);
	}

	function shareValue(uint256 _shareAmount) view public returns(uint256 _value) {
		_value = wdiv(address(this).balance, _shareAmount);
	}

	function liquidityAsPercentage(uint256 _newLiquidity) view public returns(
		uint256 _liquidityPercentage
	) {
		_liquidityPercentage = wdiv(_newLiquidity, address(this).balance);
	}
	
	function sharesAfterDeposit(uint256 _liquidityProportion) view public returns(
		uint256 _shares
	) {
		uint256 newShareSupply;

		if (shareSupply == 0 || PRECISION == _liquidityProportion) {
			newShareSupply = PRECISION;
		} else {
			newShareSupply = wdiv(shareSupply, _liquidityProportion);
		}

		_shares = sub(newShareSupply, shareSupply); 
	}

	function calculateInterest(uint256 _loanAmount) pure public returns(uint256 _interest) {
		_interest = wmul(_loanAmount, FEE);
	}

	function currentLiquidity() view external returns(uint256 _avialableLiquidity) {
		_avialableLiquidity = address(this).balance;
	}

}