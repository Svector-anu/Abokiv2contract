// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Abokiv2.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
}

contract Abokiv2Test is Test {
    Abokiv2 public aboki;
    MockERC20 public usdc;
    
    address public treasury = address(0x1);
    address public user = address(0x2);
    address public liquidityProvider = address(0x3);
    address public refundAddress = address(0x4);
    
    uint256 public constant INITIAL_BALANCE = 10000e6;
    uint256 public constant ORDER_AMOUNT = 1000e6;
    uint256 public constant PROTOCOL_FEE = 100; // 1%

    function setUp() public {
        // Deploy contracts
        aboki = new Abokiv2(treasury, PROTOCOL_FEE);
        usdc = new MockERC20("USD Coin", "USDC");
        
        // Configure token support
        aboki.setTokenSupport(address(usdc), true);
        
        // Mint tokens to user
        usdc.mint(user, INITIAL_BALANCE);
        
        // Approve contract
        vm.prank(user);
        usdc.approve(address(aboki), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(aboki.treasury(), treasury);
        assertEq(aboki.protocolFeePercent(), PROTOCOL_FEE);
        assertEq(aboki.owner(), address(this));
        assertEq(aboki.defaultFeeTier(), 3000);
    }

    function test_SetTokenSupport() public {
        address newToken = address(0x5);
        
        assertFalse(aboki.supportedTokens(newToken));
        
        aboki.setTokenSupport(newToken, true);
        assertTrue(aboki.supportedTokens(newToken));
        
        aboki.setTokenSupport(newToken, false);
        assertFalse(aboki.supportedTokens(newToken));
    }

    function test_SetTokenSupport_RevertNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        aboki.setTokenSupport(address(usdc), true);
    }

    function test_SetTokenSupport_RevertZeroAddress() public {
        vm.expectRevert("Invalid token address");
        aboki.setTokenSupport(address(0), true);
    }

    function test_SetTreasury() public {
        address newTreasury = address(0x6);
        
        aboki.setTreasury(newTreasury);
        assertEq(aboki.treasury(), newTreasury);
    }

    function test_SetTreasury_RevertZeroAddress() public {
        vm.expectRevert("Invalid treasury address");
        aboki.setTreasury(address(0));
    }

    function test_SetProtocolFeePercent() public {
        uint256 newFee = 200; // 2%
        
        aboki.setProtocolFeePercent(newFee);
        assertEq(aboki.protocolFeePercent(), newFee);
    }

    function test_SetProtocolFeePercent_RevertTooHigh() public {
        vm.expectRevert("Fee too high");
        aboki.setProtocolFeePercent(1001);
    }

    function test_SetDefaultFeeTier() public {
        aboki.setDefaultFeeTier(500);
        assertEq(aboki.defaultFeeTier(), 500);
    }

    function test_SetDefaultFeeTier_RevertUnsupported() public {
        vm.expectRevert("Fee tier not supported");
        aboki.setDefaultFeeTier(200);
    }

    function test_CreateOrder() public {
        vm.prank(user);
        uint256 orderId = aboki.createOrder(
            address(usdc),
            ORDER_AMOUNT,
            100, // rate
            refundAddress,
            liquidityProvider
        );

        assertEq(orderId, 0);

        // Check order info
        (
            address token,
            uint256 amount,
            uint256 rate,
            address creator,
            address refund,
            address lp,
            bool isFulfilled,
            bool isRefunded,
            uint256 timestamp
        ) = aboki.getOrderInfo(orderId);

        assertEq(token, address(usdc));
        assertEq(amount, ORDER_AMOUNT);
        assertEq(rate, 100);
        assertEq(creator, user);
        assertEq(refund, refundAddress);
        assertEq(lp, liquidityProvider);
        assertTrue(isFulfilled);
        assertFalse(isRefunded);
        assertGt(timestamp, 0);
    }

    function test_CreateOrder_FeeDistribution() public {
        uint256 expectedFee = (ORDER_AMOUNT * PROTOCOL_FEE) / 10000;
        uint256 expectedNet = ORDER_AMOUNT - expectedFee;

        vm.prank(user);
        aboki.createOrder(
            address(usdc),
            ORDER_AMOUNT,
            100,
            refundAddress,
            liquidityProvider
        );

        assertEq(usdc.balanceOf(treasury), expectedFee);
        assertEq(usdc.balanceOf(liquidityProvider), expectedNet);
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - ORDER_AMOUNT);
    }

    function test_CreateOrder_RevertUnsupportedToken() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS");
        unsupportedToken.mint(user, INITIAL_BALANCE);
        
        vm.startPrank(user);
        unsupportedToken.approve(address(aboki), type(uint256).max);
        
        vm.expectRevert("Token not supported");
        aboki.createOrder(
            address(unsupportedToken),
            ORDER_AMOUNT,
            100,
            refundAddress,
            liquidityProvider
        );
        vm.stopPrank();
    }

    function test_CreateOrder_RevertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert("Amount must be greater than 0");
        aboki.createOrder(
            address(usdc),
            0,
            100,
            refundAddress,
            liquidityProvider
        );
    }

    function test_CreateOrder_RevertZeroRate() public {
        vm.prank(user);
        vm.expectRevert("Rate must be greater than 0");
        aboki.createOrder(
            address(usdc),
            ORDER_AMOUNT,
            0,
            refundAddress,
            liquidityProvider
        );
    }

    function test_CreateOrder_RevertInvalidRefundAddress() public {
        vm.prank(user);
        vm.expectRevert("Invalid refund address");
        aboki.createOrder(
            address(usdc),
            ORDER_AMOUNT,
            100,
            address(0),
            liquidityProvider
        );
    }

    function test_CreateOrder_RevertInvalidLiquidityProvider() public {
        vm.prank(user);
        vm.expectRevert("Invalid liquidity provider address");
        aboki.createOrder(
            address(usdc),
            ORDER_AMOUNT,
            100,
            refundAddress,
            address(0)
        );
    }

    function test_OrderIdCounter() public {
        vm.startPrank(user);
        
        uint256 orderId1 = aboki.createOrder(
            address(usdc),
            100e6,
            100,
            refundAddress,
            liquidityProvider
        );
        
        uint256 orderId2 = aboki.createOrder(
            address(usdc),
            100e6,
            100,
            refundAddress,
            liquidityProvider
        );
        
        vm.stopPrank();

        assertEq(orderId1, 0);
        assertEq(orderId2, 1);
        assertEq(aboki.orderIdCounter(), 2);
    }

    function test_TransferOwnership() public {
        address newOwner = address(0x7);
        
        aboki.transferOwnership(newOwner);
        assertEq(aboki.owner(), newOwner);
    }

    function test_TransferOwnership_RevertZeroAddress() public {
        vm.expectRevert("Ownable: new owner is the zero address");
        aboki.transferOwnership(address(0));
    }

    function test_SupportedFeeTiers() public view {
        assertTrue(aboki.supportedFeeTiers(100));
        assertTrue(aboki.supportedFeeTiers(500));
        assertTrue(aboki.supportedFeeTiers(3000));
        assertTrue(aboki.supportedFeeTiers(10000));
        assertFalse(aboki.supportedFeeTiers(200));
    }

    function test_SetFeeTierSupport() public {
        uint24 newTier = 200;
        
        assertFalse(aboki.supportedFeeTiers(newTier));
        
        aboki.setFeeTierSupport(newTier, true);
        assertTrue(aboki.supportedFeeTiers(newTier));
        
        aboki.setFeeTierSupport(newTier, false);
        assertFalse(aboki.supportedFeeTiers(newTier));
    }

    function test_ReceiveETH() public {
        uint256 amount = 1 ether;
        vm.deal(user, amount);
        
        vm.prank(user);
        (bool success,) = address(aboki).call{value: amount}("");
        
        assertTrue(success);
        assertEq(address(aboki).balance, amount);
    }

    function testFuzz_CreateOrder(uint256 amount, uint256 rate) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);
        vm.assume(rate > 0);
        
        vm.prank(user);
        uint256 orderId = aboki.createOrder(
            address(usdc),
            amount,
            rate,
            refundAddress,
            liquidityProvider
        );

        (
            address token,
            uint256 orderAmount,
            uint256 orderRate,
            ,,,,,
        ) = aboki.getOrderInfo(orderId);

        assertEq(token, address(usdc));
        assertEq(orderAmount, amount);
        assertEq(orderRate, rate);
    }

    function testFuzz_SetProtocolFeePercent(uint256 fee) public {
        vm.assume(fee <= 1000);
        
        aboki.setProtocolFeePercent(fee);
        assertEq(aboki.protocolFeePercent(), fee);
    }
}
