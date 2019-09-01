	/**
	 * TODO
	 * 
	 * 	 	 * test and document secuirty concerns and edge cases
	 * 
	 */

pragma solidity 0.5.10;

/**
 * INTERFACES
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract DSMath {

	// adapated from the dapphub DSMath Library
	// GNU Licence blah blah blah

	uint256 constant PRECISION = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), PRECISION / 2) / PRECISION;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, PRECISION), y / 2) / y;
    }
}

contract ERC20 is IERC20, DSMath {

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, sub(_allowances[sender][msg.sender],amount));
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = sub(_balances[sender],amount);
        _balances[recipient] = add(_balances[recipient],amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = add(_totalSupply,amount);
        _balances[account] = add(_balances[account],amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = sub(_totalSupply,value);
        _balances[account] = sub(_balances[account],value);
        emit Transfer(account, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}


/**
 * MAIN CONTRACT
 */

contract Planck is ERC20 {

	/**
	 * STATE
	 */
	
	string public constant name = "Planck";
    string public constant symbol = "PLK";
    uint8 public constant decimals = 18;

	bool public reentracyGuard;
    
	uint256 public constant FEE = 3 * 10**15; //0.3%

	mapping (address => uint256) public borrowerDebt;


	/**
	 * MODIFIERS
	 */

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
	
	function provideLiquidity() external payable borrowLock {
		require(msg.value > 1 finney, "non-dust value required");
		
		//new liquidity as a percentage of total liquidity
		uint256 liquidityProportion = liquidityAsPercentage(msg.value); 
		//new shares minted to the same ratio
		uint256 sharesMinted = sharesAfterDeposit(liquidityProportion);
		//share balances updated in storage
		_mint(msg.sender, sharesMinted);
		
		emit LiquidityAdded(msg.sender, msg.value, sharesMinted);
	}

	function withdrawLiquidity(uint256 _shareAmount) external borrowLock {
		require (_shareAmount > 0, "non-zero value required");
		require (_shareAmount <= balanceOf(msg.sender), "insufficient user balance"); 
		require (_shareAmount <= totalSupply(), "insufficient global supply"); 

		//percentage and value of shares calcuated
		uint256 shareProportion = sharesAsPercentage(_shareAmount);
		uint256 shareValue = shareValue(shareProportion);
		//share balances updated in storage
		_burn(msg.sender, _shareAmount);
		//ether returned to user
		msg.sender.transfer(shareValue);

		emit LiquidityRemoved(msg.sender, shareValue, _shareAmount);
	}

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
		_sharePercentage = wdiv(_shareAmount, totalSupply());
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

		if (totalSupply() == 0 || PRECISION == _liquidityProportion) {
			newShareSupply = PRECISION;
		} else {
			newShareSupply = wdiv(totalSupply(), _liquidityProportion);
		}

		_shares = sub(newShareSupply, totalSupply()); 
	}

	function calculateInterest(uint256 _loanAmount) pure public returns(uint256 _interest) {
		_interest = wmul(_loanAmount, FEE);
	}

	function currentLiquidity() view external returns(uint256 _avialableLiquidity) {
		_avialableLiquidity = address(this).balance;
	}

}