import { uint256, int128 } from '@openzeppelin/contracts/utils/NumberUtils';
import { ERC20, TokenExchange, TokenExchangeUnderlying } from './abis/EtherFiARM.json';
import { EtherFiWithdrawQueue } from './abis/EtherFiWithdrawQueue.json';

contract EtherFiWithdrawQueue {
    // existing code ...

    function lidoWithdrawalQueueAmount() public view virtual returns (int128) {
        return _withdrawalQueueAmount;
    }

    function setLidoWithdrawalQueueAmount(int256 _newValue: int256) internal {
        require(msg.sender == _admin, "only admin can modify withdrawal queue");
        _withdrawalQueueAmount = _newValue;
    }

    modifier validLidoWithdrawalQueueAmount(int256 _newValue: int256) {
        uint256 _maxAllowedValue = uint256(uint128(_newValue)) * 10**int128(18);
        require(_newValue <= _maxAllowedValue, "new value exceeds max allowed");
        _withdrawalQueueAmount = _newValue;
        _;

    }

    function lidoWithdrawalQueueAmount(int256 _newValue: int256) public validLidoWithdrawalQueueAmount {
        // ...
    }
}