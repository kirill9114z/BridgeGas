// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBridge {
    function sendMessage(uint256 targetChainId, bytes calldata message) external payable;
}

contract GasRelayer {
    address public owner;
    IBridge public bridge;
    
    enum Status { Pending, Executed, Failed, Refunded }
    
    struct PaymentRequest {
        address user;
        uint256 amount;
        uint256 targetChainId;
        bytes transactionData;
        Status status;
        uint256 nonce;
    }
    
    mapping(uint256 => PaymentRequest) public requests;
    mapping(address => bool) public relayers;
    uint256 public feePercentage = 10; // 0.1%
    uint256 public nonceCounter;
    
    event PaymentReceived(
        uint256 indexed requestId,
        address indexed user,
        uint256 amount,
        uint256 targetChainId,
        bytes transactionData
    );
    
    event PaymentForwarded(
        uint256 indexed requestId,
        uint256 targetChainId,
        bytes message
    );
    
    event StatusUpdated(
        uint256 indexed requestId,
        Status status
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier onlyRelayer() {
        require(relayers[msg.sender], "Not relayer");
        _;
    }
    
    constructor(address _bridge) {
        owner = msg.sender;
        bridge = IBridge(_bridge);
        relayers[msg.sender] = true;
    }
    
    function payForTransaction(
        uint256 targetChainId,
        bytes calldata transactionData
    ) external payable {
        require(msg.value > 0, "Zero payment");
        
        uint256 fee = (msg.value * feePercentage) / 10000;
        uint256 lockedAmount = msg.value - fee;
        
        uint256 requestId = ++nonceCounter;
        
        requests[requestId] = PaymentRequest({
            user: msg.sender,
            amount: lockedAmount,
            targetChainId: targetChainId,
            transactionData: transactionData,
            status: Status.Pending,
            nonce: nonceCounter
        });
        
        payable(owner).transfer(fee);
        
        emit PaymentReceived(
            requestId,
            msg.sender,
            lockedAmount,
            targetChainId,
            transactionData
        );
        
        // Prepare message for target chain
        bytes memory message = abi.encode(
            requestId,
            msg.sender,
            lockedAmount,
            transactionData
        );
        emit PaymentForwarded(requestId, targetChainId, message);
    }
    
    function updateStatus(
        uint256 requestId,
        Status status
    ) external onlyRelayer {
        PaymentRequest storage request = requests[requestId];
        require(request.status == Status.Pending, "Already processed");
        
        request.status = status;
        
        if (status == Status.Failed) {
            payable(request.user).transfer(request.amount);
        } else if (status == Status.Executed) {
            // Transfer to pool (could be a separate contract)
            payable(address(this)).transfer(request.amount);
        }
        
        emit StatusUpdated(requestId, status);
    }
    
    function addRelayer(address relayer) external onlyOwner {
        relayers[relayer] = true;
    }
    
    function removeRelayer(address relayer) external onlyOwner {
        relayers[relayer] = false;
    }
    
    function withdrawPoolFunds(uint256 amount) external onlyOwner {
        payable(owner).transfer(amount);
    }
}
