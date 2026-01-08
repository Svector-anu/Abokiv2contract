// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor(address owner_) { 
        require(owner_ != address(0), "Owner: zero address");
        _owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }
    modifier onlyOwner() { require(msg.sender == _owner, "Owner: caller not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Owner: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrancy");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoter {
    function quoteExactInputSingle(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint160 sqrtPriceLimitX96) external returns (uint256 amountOut);
    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract Abokiv2 is Ownable, ReentrancyGuard {
    address public treasury;
    uint256 public protocolFeePercent; // basis points (100 = 1%)
    uint256 public orderIdCounter;
    ISwapRouter public uniswapRouter;
    IQuoter public quoter;
    address public WETH;
    mapping(address => bool) public supportedTokens;
    mapping(uint24 => bool) public supportedFeeTiers;
    uint24 public defaultFeeTier;

    struct Order {
        address token;
        uint256 amount;
        uint256 rate;
        address creator;
        address refundAddress;
        address liquidityProvider;
        bool isFulfilled;
        bool isRefunded;
        uint256 timestamp;
    }
    mapping(uint256 => Order) public orders;

    event OrderCreated(uint256 indexed orderId, address indexed token, uint256 amount, uint256 rate, address refundAddress, address liquidityProvider);
    event OrderFulfilled(uint256 indexed orderId, address indexed liquidityProvider);
    event OrderRefunded(uint256 indexed orderId);
    event TokenSupportUpdated(address indexed token, bool isSupported);
    event TreasuryUpdated(address indexed newTreasury);
    event ProtocolFeeUpdated(uint256 newFeePercent);
    event RouterUpdated(address indexed uniswapRouter);
    event WETHUpdated(address indexed weth);
    event SwapExecuted(address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);
    event QuoterUpdated(address indexed quoter);
    event FeeTierUpdated(uint24 indexed feeTier, bool isSupported);
    event DefaultFeeTierUpdated(uint24 feeTier);

    receive() external payable {}

    constructor(address _treasury, uint256 _protocolFeePercent) Ownable(msg.sender) {
        require(_treasury != address(0), "Init: Treasury zero address");
        require(_protocolFeePercent <= 1000, "Init: Fee too high"); // Max 10%
        treasury = _treasury;
        protocolFeePercent = _protocolFeePercent;
        // Supported UniswapV3 fee tiers (basis points)
        supportedFeeTiers[100] = true;
        supportedFeeTiers[500] = true;
        supportedFeeTiers[3000] = true;
        supportedFeeTiers[10000] = true;
        defaultFeeTier = 3000;
    }

    function setUniswapRouter(address _router) external onlyOwner {
        require(_router != address(0), "Router: zero address");
        uniswapRouter = ISwapRouter(_router);
        emit RouterUpdated(_router);
    }

    function setQuoter(address _quoter) external onlyOwner {
        require(_quoter != address(0), "Quoter: zero address");
        quoter = IQuoter(_quoter);
        emit QuoterUpdated(_quoter);
    }

    function setWETH(address _weth) external onlyOwner {
        require(_weth != address(0), "WETH: zero address");
        WETH = _weth;
        emit WETHUpdated(_weth);
    }

    function setTokenSupport(address _token, bool _isSupported) external onlyOwner {
        require(_token != address(0), "Token: zero address");
        supportedTokens[_token] = _isSupported;
        emit TokenSupportUpdated(_token, _isSupported);
    }

    function setFeeTierSupport(uint24 _feeTier, bool _isSupported) external onlyOwner {
        supportedFeeTiers[_feeTier] = _isSupported;
        emit FeeTierUpdated(_feeTier, _isSupported);
    }

    function setDefaultFeeTier(uint24 _feeTier) external onlyOwner {
        require(supportedFeeTiers[_feeTier], "FeeTier: not supported");
        defaultFeeTier = _feeTier;
        emit DefaultFeeTierUpdated(_feeTier);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury: zero address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        require(_protocolFeePercent <= 1000, "Fee: too high");
        protocolFeePercent = _protocolFeePercent;
        emit ProtocolFeeUpdated(_protocolFeePercent);
    }

    function createOrder(
        address _token,
        uint256 _amount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external nonReentrant returns (uint256 orderId) {
        require(supportedTokens[_token], "Order: token not supported");
        require(_amount > 0, "Order: zero amount");
        require(_rate > 0, "Order: zero rate");
        require(_refundAddress != address(0), "Order: refund zero address");
        require(_liquidityProvider != address(0), "Order: lp zero address");

        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Order: transferFrom failed");

        uint256 feeAmount = (_amount * protocolFeePercent) / 10000;
        uint256 netAmount = _amount - feeAmount;

        if (feeAmount > 0) require(token.transfer(treasury, feeAmount), "Order: fee transfer failed");
        require(token.transfer(_liquidityProvider, netAmount), "Order: LP transfer failed");

        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: _token,
            amount: _amount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            liquidityProvider: _liquidityProvider,
            isFulfilled: true,
            isRefunded: false,
            timestamp: block.timestamp
        });

        emit OrderCreated(orderId, _token, _amount, _rate, _refundAddress, _liquidityProvider);
        emit OrderFulfilled(orderId, _liquidityProvider);
    }

    function createOrderWithSwap(
        address _targetToken,
        uint256 _minOutputAmount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external payable nonReentrant returns (uint256 orderId) {
        require(msg.value > 0, "OrderSwap: no ETH sent");
        require(_minOutputAmount > 0, "OrderSwap: minOutput zero");
        require(supportedTokens[_targetToken], "OrderSwap: target token not supported");
        require(_refundAddress != address(0), "OrderSwap: refund zero address");
        require(_liquidityProvider != address(0), "OrderSwap: lp zero address");
        require(address(uniswapRouter) != address(0), "OrderSwap: router unset");
        require(WETH != address(0), "OrderSwap: WETH unset");

        uint256 inputAmount = msg.value;
        IWETH(WETH).deposit{value: inputAmount}();
        require(IERC20(WETH).approve(address(uniswapRouter), inputAmount), "OrderSwap: approve failed");

        uint256 outputAmount;
        try uniswapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: _targetToken,
                fee: defaultFeeTier,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: inputAmount,
                amountOutMinimum: _minOutputAmount,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 amountOut) {
            outputAmount = amountOut;
            emit SwapExecuted(WETH, _targetToken, inputAmount, outputAmount);
        } catch {
            IWETH(WETH).withdraw(inputAmount);
            (bool success, ) = _refundAddress.call{value: inputAmount}("");
            require(success, "OrderSwap: ETH refund failed");
            revert("OrderSwap: swap failed");
        }

        uint256 feeAmount = (outputAmount * protocolFeePercent) / 10000;
        uint256 netAmount = outputAmount - feeAmount;
        if (feeAmount > 0) require(IERC20(_targetToken).transfer(treasury, feeAmount), "OrderSwap: fee transfer failed");
        require(IERC20(_targetToken).transfer(_liquidityProvider, netAmount), "OrderSwap: LP transfer failed");

        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: _targetToken,
            amount: outputAmount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            liquidityProvider: _liquidityProvider,
            isFulfilled: true,
            isRefunded: false,
            timestamp: block.timestamp
        });

        emit OrderCreated(orderId, _targetToken, outputAmount, _rate, _refundAddress, _liquidityProvider);
        emit OrderFulfilled(orderId, _liquidityProvider);
    }

    function createOrderWithCustomPath(
        address[] calldata _path,
        uint256 _inputAmount,
        uint256 _minOutputAmount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external nonReentrant returns (uint256 orderId) {
        require(address(uniswapRouter) != address(0), "CustomPath: router unset");
        require(_path.length >= 2, "CustomPath: path too short");
        require(_inputAmount > 0, "CustomPath: input zero");
        require(_minOutputAmount > 0, "CustomPath: minOutput zero");
        address targetToken = _path[_path.length - 1];
        require(supportedTokens[targetToken], "CustomPath: target token not supported");
        require(_refundAddress != address(0), "CustomPath: refund zero address");
        require(_liquidityProvider != address(0), "CustomPath: lp zero address");

        IERC20 inputToken = IERC20(_path[0]);
        require(inputToken.transferFrom(msg.sender, address(this), _inputAmount), "CustomPath: transferFrom failed");
        require(inputToken.approve(address(uniswapRouter), _inputAmount), "CustomPath: approve failed");

        uint256 outputAmount;
        bytes memory encodedPath = _encodeV3Path(_path);
        try uniswapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: encodedPath,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: _inputAmount,
                amountOutMinimum: _minOutputAmount
            })
        ) returns (uint256 amountOut) {
            outputAmount = amountOut;
            emit SwapExecuted(_path[0], targetToken, _inputAmount, outputAmount);
        } catch {
            require(inputToken.transfer(msg.sender, _inputAmount), "CustomPath: refund failed");
            revert("CustomPath: swap failed");
        }

        uint256 feeAmount = (outputAmount * protocolFeePercent) / 10000;
        uint256 netAmount = outputAmount - feeAmount;

        IERC20 targetTokenContract = IERC20(targetToken);
        if (feeAmount > 0) require(targetTokenContract.transfer(treasury, feeAmount), "CustomPath: fee transfer failed");
        require(targetTokenContract.transfer(_liquidityProvider, netAmount), "CustomPath: LP transfer failed");

        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: targetToken,
            amount: outputAmount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            liquidityProvider: _liquidityProvider,
            isFulfilled: true,
            isRefunded: false,
            timestamp: block.timestamp
        });

        emit OrderCreated(orderId, targetToken, outputAmount, _rate, _refundAddress, _liquidityProvider);
        emit OrderFulfilled(orderId, _liquidityProvider);
    }

    function estimateSwapOutput(
        address _inputToken,
        address _targetToken,
        uint256 _inputAmount
    ) external returns (uint256) {
        require(address(quoter) != address(0), "Quoter: not set");
        return quoter.quoteExactInputSingle(
            _inputToken, _targetToken, defaultFeeTier, _inputAmount, 0
        );
    }

    function estimateSwapOutputWithPath(
        address[] calldata _path,
        uint256 _inputAmount
    ) external returns (uint256) {
        require(address(quoter) != address(0), "Quoter: not set");
        require(_path.length >= 2, "Quoter: path too short");
        return quoter.quoteExactInput(_encodeV3Path(_path), _inputAmount);
    }

    function getOrderInfo(uint256 _orderId) external view returns (
        address token,
        uint256 amount,
        uint256 rate,
        address creator,
        address refundAddress,
        address liquidityProvider,
        bool isFulfilled,
        bool isRefunded,
        uint256 timestamp
    ) {
        Order storage order = orders[_orderId];
        return (
            order.token,
            order.amount,
            order.rate,
            order.creator,
            order.refundAddress,
            order.liquidityProvider,
            order.isFulfilled,
            order.isRefunded,
            order.timestamp
        );
    }

    function _encodeV3Path(address[] calldata _tokens) internal view returns (bytes memory) {
        require(_tokens.length >= 2, "EncodePath: too short");
        bytes memory path = abi.encodePacked(_tokens[0]);
        for (uint i = 1; i < _tokens.length; i++) {
            path = abi.encodePacked(path, defaultFeeTier, _tokens[i]);
        }
        return path;
    }
}