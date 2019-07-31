pragma solidity 0.5.10;

/**
 * INTERFACE
 */

contract Planck {
    function borrow(uint256 _ethAmount) external {}
    function repayDebt(address _borrower) public payable {}
    function borrowerDebt(address _borrower) public view returns(uint256) {}
    function currentLiquidity() external view returns(uint256) {}
}

/**
 * MAIN CONTRACT
 */

contract Borrower {

    uint256 public simpleState;
    
    Planck public planck;

    constructor(Planck _planck) public {
        planck = _planck;
    }
    
    function() payable external {
        changeState();
    }

    function changeState() public returns(bool _res, bytes memory _data){
        //simple change of state, but could do all sorts of crazy stuff here
        simpleState++;
        //query debt, could also be handled internally
        uint256 debt = planck.borrowerDebt(address(this));
        //raw call method, could also use repayDebt        
        (_res, _data) = address(planck).call.value(debt)("");
        return (_res, _data);
    }

    function deposit() payable external {}
    
    function planckLiquidity() public view returns(uint256) {
        return planck.currentLiquidity();
    }
        
    function borrowFrom(uint256 _ethAmount) external {
        planck.borrow(_ethAmount);
    }
    
    function getBalance() view external returns(uint256) {
        return address(this).balance;
    }
    
}