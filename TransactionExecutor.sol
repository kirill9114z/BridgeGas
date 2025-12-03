// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ISwapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract TransactionExecutor {
    address public owner;
    address public gasRelayer;
    mapping(address => bool) public authorizedRelayers;
    
    struct ExecutionRequest {
        address user;
        uint256 amount;
        bytes transactionData;
        bool executed;
    }
    
    mapping(uint256 => ExecutionRequest) public executions;
    mapping(address => bool) public approvedTokens;
    mapping(address => bool) public approvedRouters;
    
    event ExecutionStarted(
        uint256 indexed requestId,
        address indexed user,
        uint256 amount,
        bytes transactionData
    );
    
    event ExecutionCompleted(
        uint256 indexed requestId,
        bool success
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier onlyAuthorizedRelayer() {
        require(authorizedRelayers[msg.sender], "Not authorized");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        authorizedRelayers[msg.sender] = true;
    }
    
    function executeTransaction(
        uint256 requestId,
        address user,
        uint256 amount,
        bytes calldata transactionData
    ) external onlyAuthorizedRelayer returns (bool) {
        require(!executions[requestId].executed, "Already executed");
        
        executions[requestId] = ExecutionRequest({
            user: user,
            amount: amount,
            transactionData: transactionData,
            executed: false
        });
        
        emit ExecutionStarted(requestId, user, amount, transactionData);
        
        (bool success, ) = decodeAndExecute(transactionData, user);
        
        executions[requestId].executed = true;
        
        // Notify source chain about execution result
        emit ExecutionCompleted(requestId, success);
        
        return success;
    }
    
    function decodeAndExecute(
        bytes memory data,
        address user
    ) internal returns (bool, bytes memory) {
        (
            address router,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin,
            uint256 deadline
        ) = abi.decode(data, (address, address, address, uint256, uint256, uint256));
        
        require(approvedRouters[router], "Router not approved");
        require(approvedTokens[tokenIn], "TokenIn not approved");
        require(approvedTokens[tokenOut], "TokenOut not approved");
        
        // Transfer tokens from user (should be pre-approved)
        IERC20(tokenIn).transferFrom(user, address(this), amountIn);
        
        // Approve router to spend tokens
        IERC20(tokenIn).approve(router, amountIn);
        
        // Execute swap
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        try ISwapRouter(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            user, 
            deadline
        ) returns (uint256[] memory amounts) {
            return (true, abi.encode(amounts));
        } catch {
            // Return tokens to user if swap fails
            IERC20(tokenIn).transfer(user, amountIn);
            return (false, bytes("Swap failed"));
        }
    }
    
    function onMessageReceived(
        uint256 sourceChainId,
        uint256 requestId,
        address user,
        uint256 amount,
        bytes calldata transactionData
    ) external onlyAuthorizedRelayer {
        executeTransaction(requestId, user, amount, transactionData);
    }
    
    function addApprovedToken(address token) external onlyOwner {
        approvedTokens[token] = true;
    }
    
    function addApprovedRouter(address router) external onlyOwner {
        approvedRouters[router] = true;
    }
    
    function addAuthorizedRelayer(address relayer) external onlyOwner {
        authorizedRelayers[relayer] = true;
    }
    
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}
