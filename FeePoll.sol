// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract FeePool {
    address public owner;
    mapping(address => uint256) public relayerBalances;
    
    event FeeDistributed(address indexed relayer, uint256 amount);
    event FeesWithdrawn(address indexed relayer, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function depositFees(address relayer) external payable {
        relayerBalances[relayer] += msg.value;
        emit FeeDistributed(relayer, msg.value);
    }
    
    function withdrawFees(uint256 amount) external {
        require(relayerBalances[msg.sender] >= amount, "Insufficient balance");
        
        relayerBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        
        emit FeesWithdrawn(msg.sender, amount);
    }
    
    function distributeFees(
        address[] calldata relayers,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(relayers.length == amounts.length, "Arrays length mismatch");
        
        uint256 total;
        for(uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        
        require(address(this).balance >= total, "Insufficient pool balance");
        
        for(uint256 i = 0; i < relayers.length; i++) {
            relayerBalances[relayers[i]] += amounts[i];
            emit FeeDistributed(relayers[i], amounts[i]);
        }
    }
}
