// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Simple IERC20 interface
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Simple Ownable
abstract contract Ownable {
    address private _owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    constructor(address owner_) {
        _owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }
    
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
    }
}

// Simple ReentrancyGuard
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    constructor() {
        _status = _NOT_ENTERED;
    }
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// Uniswap V3 Router interface
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

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

// Uniswap V3 Quoter interface
interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    function quoteExactInput(bytes memory path, uint256 amountIn)
        external returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/**
 * @title Abokiv2
 * @dev A contract that allows users to create crypto exchange orders
 * and processes them through Uniswap V3. Same functionality as V2 but with V3 routing!
 */
contract Abokiv2 is Ownable, ReentrancyGuard {
    // State variables
    address public treasury;
    uint256 public protocolFeePercent; // Fee in basis points (100 = 1%)
    uint256 public orderIdCounter;
    ISwapRouter public uniswapRouter;
    IQuoter public quoter;
    address public WETH;
    
    // Mapping to track supported tokens
    mapping(address => bool) public supportedTokens;
    
    // V3 specific: supported fee tiers
    mapping(uint24 => bool) public supportedFeeTiers;
    uint24 public defaultFeeTier; // Default fee tier to use when not specified
    
    // Order struct
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
    
    // Mapping to store orders by ID
    mapping(uint256 => Order) public orders;
    
    // Events
    event OrderCreated(uint256 orderId, address token, uint256 amount, uint256 rate, address refundAddress, address liquidityProvider);
    event OrderFulfilled(uint256 orderId, address liquidityProvider);
    event OrderRefunded(uint256 orderId);
    event TokenSupportUpdated(address token, bool isSupported);
    event TreasuryUpdated(address newTreasury);
    event ProtocolFeeUpdated(uint256 newFeePercent);
    event RouterUpdated(address uniswapRouter);
    event WETHUpdated(address weth);
    event SwapExecuted(address fromToken, address toToken, uint256 amountIn, uint256 amountOut);
    event QuoterUpdated(address quoter);
    event FeeTierUpdated(uint24 feeTier, bool isSupported);
    event DefaultFeeTierUpdated(uint24 feeTier);
    
    // Receive function
    receive() external payable {}
    
    constructor(address _treasury, uint256 _protocolFeePercent) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_protocolFeePercent <= 1000, "Fee too high"); // Max 10%

        treasury = _treasury;
        protocolFeePercent = _protocolFeePercent;
        
        // Initialize V3 fee tiers
        supportedFeeTiers[100] = true;   // 0.01%
        supportedFeeTiers[500] = true;   // 0.05%
        supportedFeeTiers[3000] = true;  // 0.30%
        supportedFeeTiers[10000] = true; // 1.00%
        defaultFeeTier = 3000; // Default to 0.3%
    }
    
    /**
     * @dev Sets the Uniswap V3 Router address
     */
    function setUniswapRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router address");
        uniswapRouter = ISwapRouter(_router);
        emit RouterUpdated(_router);
    }
    
    /**
     * @dev Sets the Uniswap V3 Quoter address
     */
    function setQuoter(address _quoter) external onlyOwner {
        require(_quoter != address(0), "Invalid quoter address");
        quoter = IQuoter(_quoter);
        emit QuoterUpdated(_quoter);
    }
    
    /**
     * @dev Sets the WETH address
     */
    function setWETH(address _weth) external onlyOwner {
        require(_weth != address(0), "Invalid WETH address");
        WETH = _weth;
        emit WETHUpdated(_weth);
    }
    
    /**
     * @dev Sets token support status
     */
    function setTokenSupport(address _token, bool _isSupported) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        supportedTokens[_token] = _isSupported;
        emit TokenSupportUpdated(_token, _isSupported);
    }
    
    /**
     * @dev Sets fee tier support status
     */
    function setFeeTierSupport(uint24 _feeTier, bool _isSupported) external onlyOwner {
        supportedFeeTiers[_feeTier] = _isSupported;
        emit FeeTierUpdated(_feeTier, _isSupported);
    }
    
    /**
     * @dev Sets default fee tier
     */
    function setDefaultFeeTier(uint24 _feeTier) external onlyOwner {
        require(supportedFeeTiers[_feeTier], "Fee tier not supported");
        defaultFeeTier = _feeTier;
        emit DefaultFeeTierUpdated(_feeTier);
    }
    
    /**
     * @dev Updates the treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
    
    /**
     * @dev Updates the protocol fee percentage
     */
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        require(_protocolFeePercent <= 1000, "Fee too high"); // Max 10%
        protocolFeePercent = _protocolFeePercent;
        emit ProtocolFeeUpdated(_protocolFeePercent);
    }
    
    /**
     * @dev Creates a new exchange order
     */
    function createOrder(
        address _token,
        uint256 _amount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external nonReentrant returns (uint256 orderId) {
        require(supportedTokens[_token], "Token not supported");
        require(_amount > 0, "Amount must be greater than 0");
        require(_rate > 0, "Rate must be greater than 0");
        require(_refundAddress != address(0), "Invalid refund address");
        require(_liquidityProvider != address(0), "Invalid liquidity provider address");
        
        // Transfer tokens from user to contract
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        // Calculate protocol fee
        uint256 feeAmount = (_amount * protocolFeePercent) / 10000;
        uint256 netAmount = _amount - feeAmount;
        
        // Transfer fee to treasury and tokens to liquidity provider
        if (feeAmount > 0) {
            require(token.transfer(treasury, feeAmount), "Fee transfer failed");
        }
        require(token.transfer(_liquidityProvider, netAmount), "Liquidity provider transfer failed");
        
        // Create order
        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: _token,
            amount: _amount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            liquidityProvider: _liquidityProvider,
            isFulfilled: true, // Auto-fulfilled
            isRefunded: false,
            timestamp: block.timestamp
        });
        
        emit OrderCreated(orderId, _token, _amount, _rate, _refundAddress, _liquidityProvider);
        emit OrderFulfilled(orderId, _liquidityProvider);
    }
    
    /**
     * @dev Creates order by swapping ETH to supported token
     */
    function createOrderWithSwap(
        address _targetToken,
        uint256 _minOutputAmount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external payable nonReentrant returns (uint256 orderId) {
        require(msg.value > 0, "ETH required");
        require(_minOutputAmount > 0, "Min output amount must be greater than 0");
        require(supportedTokens[_targetToken], "Target token not supported");
        require(_refundAddress != address(0), "Invalid refund address");
        require(_liquidityProvider != address(0), "Invalid liquidity provider");
        require(address(uniswapRouter) != address(0), "Uniswap router not set");
        require(WETH != address(0), "WETH address not set");

        uint256 inputAmount = msg.value;

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: inputAmount}();
        IERC20(WETH).approve(address(uniswapRouter), inputAmount);

        uint256 outputAmount;

        // Execute V3 swap
        try uniswapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: _targetToken,
                fee: defaultFeeTier, // Use default fee tier
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
            // Unwrap WETH back to ETH
            IWETH(WETH).withdraw(inputAmount);
            
            // Transfer ETH to refund address
            (bool success, ) = _refundAddress.call{value: inputAmount}("");
            require(success, "ETH refund failed");
            
            revert("Swap failed");
        }

        // Calculate and deduct fee
        uint256 feeAmount = (outputAmount * protocolFeePercent) / 10000;
        uint256 netAmount = outputAmount - feeAmount;

        if (feeAmount > 0) {
            IERC20(_targetToken).transfer(treasury, feeAmount);
        }
        IERC20(_targetToken).transfer(_liquidityProvider, netAmount);

        // Store order
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

    /**
     * @dev Creates order using custom token path
     */
    function createOrderWithCustomPath(
        address[] calldata _path,
        uint256 _inputAmount,
        uint256 _minOutputAmount,
        uint256 _rate,
        address _refundAddress,
        address _liquidityProvider
    ) external nonReentrant returns (uint256 orderId) {
        // Validate inputs
        require(address(uniswapRouter) != address(0), "Uniswap router not set");
        require(_path.length >= 2, "Path too short");
        require(_inputAmount > 0, "Input amount must be greater than 0");
        require(_minOutputAmount > 0, "Min output amount must be greater than 0");
        require(supportedTokens[_path[_path.length - 1]], "Target token not supported");
        require(_refundAddress != address(0), "Invalid refund address");
        require(_liquidityProvider != address(0), "Invalid liquidity provider address");
        
        // Transfer input tokens from user to contract
        IERC20 inputToken = IERC20(_path[0]);
        require(inputToken.transferFrom(msg.sender, address(this), _inputAmount), "Transfer failed");
        
        // Approve router to spend the input tokens
        require(inputToken.approve(address(uniswapRouter), _inputAmount), "Approval failed");
        
        uint256 outputAmount;
        address targetToken = _path[_path.length - 1];
        
        // Convert V2 path to V3 encoded path
        bytes memory encodedPath = _encodeV3Path(_path);
        
        // Execute V3 swap
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
            // Refund the user if the swap fails
            require(inputToken.transfer(msg.sender, _inputAmount), "Refund failed");
            revert("Swap failed");
        }
        
        // Calculate protocol fee
        uint256 feeAmount = (outputAmount * protocolFeePercent) / 10000;
        uint256 netAmount = outputAmount - feeAmount;
        
        // Transfer fee to treasury and tokens to liquidity provider
        IERC20 targetTokenContract = IERC20(targetToken);
        if (feeAmount > 0) {
            require(targetTokenContract.transfer(treasury, feeAmount), "Fee transfer failed");
        }
        require(targetTokenContract.transfer(_liquidityProvider, netAmount), "Liquidity provider transfer failed");
        
        // Create the order with the swapped tokens
        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: targetToken,
            amount: outputAmount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            liquidityProvider: _liquidityProvider,
            isFulfilled: true, // Auto-fulfilled
            isRefunded: false,
            timestamp: block.timestamp
        });
        
        emit OrderCreated(orderId, targetToken, outputAmount, _rate, _refundAddress, _liquidityProvider);
        emit OrderFulfilled(orderId, _liquidityProvider);
    }
    
    /**
     * @dev Estimates swap output
     */
    function estimateSwapOutput(
        address _inputToken,
        address _targetToken,
        uint256 _inputAmount
    ) external returns (uint256) {
        require(address(quoter) != address(0), "Quoter not set");
        
        return quoter.quoteExactInputSingle(
            _inputToken,
            _targetToken,
            defaultFeeTier, // Use default fee tier
            _inputAmount,
            0
        );
    }
    
    /**
     * @dev Estimates swap output with custom path
     */
    function estimateSwapOutputWithPath(
        address[] calldata _path,
        uint256 _inputAmount
    ) external returns (uint256) {
        require(address(quoter) != address(0), "Quoter not set");
        require(_path.length >= 2, "Path too short");
        
        bytes memory encodedPath = _encodeV3Path(_path);
        return quoter.quoteExactInput(encodedPath, _inputAmount);
    }
    
    /**
     * @dev Gets order information
     */
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
    
    /**
     * @dev Internal function to convert V2 style path to V3 encoded path
     */
    function _encodeV3Path(address[] calldata _tokens) internal view returns (bytes memory) {
        require(_tokens.length >= 2, "Path too short");
        
        bytes memory path = abi.encodePacked(_tokens[0]);
        
        for (uint i = 1; i < _tokens.length; i++) {
            path = abi.encodePacked(path, defaultFeeTier, _tokens[i]);
        }
        
        return path;
    }
}