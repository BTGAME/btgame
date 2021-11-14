pragma solidity >=0.5.0 <0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract BTG is ERC20 {
  string public name = "BTG";
  string public symbol = "BTG";
  uint8 public decimals = 18;

  //发行代币总数量
  uint public INITIAL_SUPPLY = 10**25;

  constructor() public {
    _mint(msg.sender, INITIAL_SUPPLY);
  }

}
