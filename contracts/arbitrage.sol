pragma solidity ^0.5.0;

import "./interfaces/FlashLoanReceiverBase.sol";
import "./interfaces/ILendingPoolAddressesProvider.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IDefi.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IPancakeCallee.sol";
import "./interfaces/IERC20.sol";


contract ArbitrageBNB is FlashLoanReceiverBase {

    address public constant pancakeFactory;
    address public defi;
    IUniswapV2Router02 public bakeryRouter;

    constructor(address _pancakeFactory, address _bakeryRouter) public {
        pancakeFactory = _pancakeFactory;
        bakeryRouter = IUniswapV2Router02(_bakeryRouter)
        defi = _defi;
    }

    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external {
        require(
            _amount <= getBalanceInternal(address(this), _reserve),
            "Invalid balance, was the flashLoan successful?"
        );

        //
        // Your logic goes here.
        // !! Ensure that *this contract* has enough of `_reserve` funds to payback the `_fee` !!
        //

        IDefi app = IDefi(defi);
        // Todo: Deposit into defi smart contract
        app.depositBNB.value(_amount)(_amount);
        
        // Todo: Withdraw from defi smart contract
        app.withdraw(_amount);


        uint256 totalDebt = _amount.add(_fee);
        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }
    
    function startArbitrage(
        address token0,
        address token1,
        uint amount0,
        uint amount1
    ) external {
        address pairAddress = IUniswapV2Factory(pancakeFactory).getPair(token0, token1)
        require(pairAddress != address(0), 'This pool does not exist')
        IUniswapV2Pair(pairAddress).swap(
            amount0,
            amount1,
            address(this),
            bytes('not empty')
        );
    }

    function pancakeCall(
        address _sender,
        uint _amount0,
        uint _amount1,
        bytes calldata _data
    ) external {
        address[] memory path = new address[](2)
        uint amountToken = _amount0 == 0 ? _amount1 : _amount0;

        address token0 = IUniswapV2Pair(msg.sender).token0()
        address token1 = IUniswapV2Pair(msg.sender).token1() 

        require(msg.sender == UniswapV2Library.pairFor(pancakeFactory, token0, token1), 'Unauthorized');
        require(_amount0 == 0 || _amount1 == 0)

        IERC20 token = IERC20(_amount0 == 0 ? token1: token0);

        token.approve(address(bakeryRouter), amountToken);
        uint amountRequired = UniswapV2Library.getAmountsIn(
            pancakeFactory,
            amountToken,
            path
        )[0];
        uint amountReceived = bakeryRouter.swapExactTokensForTokens(
            amountToken, 
            amountRequired,
            path,
            msg.sender,
            deadline
        )[1];

        IERC20 otherToken = IERC20(_amount0 == 0 ? token0 : token1)
        otherToken.transfer(msg.sender, amountRequired);
        otherToken.transfer(tx.origin, amountReceived - amountRequired)

    }

    function flashloanBnb(uint256 _amount) public  {
        bytes memory data = "";
       
        ILendingPool lendingPool = ILendingPool(
            addressesProvider.getLendingPool()
        );
        lendingPool.flashLoan(address(this), BNB_ADDRESS, _amount, data);
    }
    
}