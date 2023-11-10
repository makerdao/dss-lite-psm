// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.16;

interface ChainlogLike {
    function getAddress(bytes32) external returns (address);
}

interface DssLitePsmLike {
    function file(bytes32, uint256) external;
}

interface AuthorityLike {
    function canCall(address, address, bytes4) external view returns (bool);
}

/**
 * @title A mom for `DssLitePsm` instances.
 * @notice Bypass governance delay to set `tin` and `tout` for a `DssLitePsm` instance.
 */
contract DssLitePsmMom {
    /// @notice The MakerDAO contract registry.
    ChainlogLike public immutable chainlog;

    /// @notice The owner of this contract.
    address public owner;
    /// @notice The authority to delegate authentication to.
    address public authority;
    /// @notice The chainlog keys for `DssLitePsm` instances controlled by this contract. `instances[address]`
    mapping(bytes32 => uint256) public keys;

    /**
     * @notice The owner of this contract was set.
     * @param _owner The new owner.
     */
    event SetOwner(address indexed _owner);
    /**
     * @notice The authority of this contract was set.
     * @param _authority The new authority.
     */
    event SetAuthority(address indexed _authority);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, uint256 data);

    modifier onlyOwner() {
        require(msg.sender == owner, "DssLitePsmMom/not-owner");
        _;
    }

    modifier auth() {
        require(isAuthorized(msg.sender, msg.sig), "DssLitePsmMom/not-authorized");
        _;
    }

    /**
     * @notice Returns whether or not the function identified by `sig` can be called by `src`.
     * @param src The caller address.
     * @param sig The selector of the function being called.
     */
    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if(src == owner) {
            return true;
        } else if(authority == address(0)) {
            return false;
        } else {
            return AuthorityLike(authority).canCall(src, address(this), sig);
        }
    }

    /**
     * @param chainlog_ The MakerDAO contract registry.
     */
    constructor(address chainlog_) {
        chainlog = ChainlogLike(chainlog_);

        owner = msg.sender;
        emit SetOwner(msg.sender);
    }

    /*//////////////////////////////////
       Governance actions with delay
    //////////////////////////////////*/

    /**
     * @notice Sets a new owner for this contract;
     * @param owner_ The new owner address.
     */
    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        emit SetOwner(owner_);
    }

    /**
     * @notice Sets a new authority for this contract;
     * @param authority_ The new authority address.
     */
    function setAuthority(address authority_) external onlyOwner {
        authority = authority_;
        emit SetAuthority(authority_);
    }

    /*//////////////////////////////////
      Governance actions without delay
    //////////////////////////////////*/

    function file(bytes32 key, bytes32 what, uint256 data) external auth {
        require(what == "tin" || what == "tout", "DssLitePsmMom/file-unrecognized-param");
        DssLitePsmLike(chainlog.getAddress(key)).file(what, data);
        emit File(what, data);
    }
}
