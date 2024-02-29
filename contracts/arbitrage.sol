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

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'Pancake: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Pancake: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { 
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'Pancake: INVALID_TO');
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IPancakeCallee(to).pancakeCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Pancake: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(2));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(2));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'Pancake: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
}