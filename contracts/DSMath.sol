pragma solidity 0.5.10;

contract DSMath {

	// lightly adapated from the dapphub DSMath Library: https://github.com/dapphub/ds-math
    // removed unused funtions and anything called a "WAD"
    // GNU General Public License v3.0, etc

	uint256 constant PRECISION = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), PRECISION / 2) / PRECISION;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, PRECISION), y / 2) / y;
    }
}
