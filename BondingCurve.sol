pragma solidity ^0.5.0;


import "openzeppelin-eth/contracts/math/SafeMath.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20Detailed.sol";
import "zos-lib/contracts/Initializable.sol";

contract BondingCurve is Initializable, ERC20, ERC20Detailed {

    using SafeMath for uint256;

    uint256 public reserve;

    event CurveBuy(uint256 amount, uint256 paid, uint256 indexed when);
    event CurveSell(uint256 amount, uint256 rewarded, uint256 indexed when);

    function initialize(string memory name, string memory symbol, uint8 decimals) public initializer {
        ERC20Detailed.initialize(name, symbol, decimals);
    }

    /**
     * Curve function interfaces 
     */
    function calculatePurchaseReturn(uint256 tokens) public view returns (uint256 thePrice);
    function calculateSaleReturn(uint256 tokens) public view returns (uint256 theReward);


    function buy(uint256 tokens) public payable {
        require(tokens > 0, "Must request non-zero amount of tokens.");

        uint256 paid = calculatePurchaseReturn(tokens);
        require(
            msg.value >= paid,
            "Did not send enough ether to buy!"
        );

        reserve = reserve.add(paid);
        _mint(msg.sender, tokens);
        //extra funds handling
        if (msg.value > paid) {
            msg.sender.transfer(msg.value.sub(paid));
        }

        emit CurveBuy(tokens, paid, now);
    }

    function sell(uint256 tokens)
        public returns (uint256 rewarded)
    {
        require(tokens > 0, "Must spend non-zero amount of tokens.");
        require(
            balanceOf(msg.sender) >= tokens,
            "Sender does not have enough tokens to spend."
        );

        rewarded = calculateSaleReturn(tokens);
        reserve = reserve.sub(rewarded);
        _burn(msg.sender, tokens);
        msg.sender.transfer(rewarded);

        emit CurveSell(tokens, rewarded, now);
    }
    
}
