/pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Enumerable.sol";
import "./utils/StringLength.sol";
import "openzeppelin-solidity/contracts/drafts/Counters.sol";

contract Registry is ERC721Full {
    constructor() ERC721Full("VeChain Name Service", "VNS") public {

    }

    struct Auction {
        uint        auctionID;
        uint        winningBid;
        address     winningBidder;
        uint        auctionEnd;
        string      domainName;
    }

    // Mapping from token to domain name
    mapping(uint256 => string) private _tokenDomain;

    // Mapping from domain to address
    mapping(string => address) private _domainAddress;

    // Public Functions
    function startAuction() {
        // Check that a domain has not been registered and start a new auction
        // Reserve the domain name in the pending mapping, preventing duplicate auctions
    }

    function bidOnAuction() {
        // Bid on an auction that is currently active
    }

    function finalizeAuction() {
        // Once an auction has passed its expiry, anyone (usually the winner) can call to finalize the auction and create the domain
    }

    // Private Functions
    function registerDomain(string memory _domainName, address _owner) internal {
        require(verifyNewDomain(_domainName));

        uint256 _tokenID = current();                   // tokenID is equal to its count
        _mint(_owner, _tokenID);                        // Call the mint function of ERC721Enumerable
        increment();                                    // Increment counter after minting

        // Set VNS Specific Data
        _tokenDomain[_tokenID] = _domainName;           // Link the tokenID to the current address
        _domainAddress[_domainName] = _owner;           // Intialize the address to point at the owner
    }

    function destroyToken(address _owner, uint256 _tokenID) internal {
        _burn(_owner, _tokenID);

        // Reset VNS Specific Data
        string _domainName = _tokenDomain[_tokenID];
        _tokenDomain[_tokenID] = "";                    // Reset token to domain name
        _domainAddress[_domainName] = address(0);       // Reset domain name to 0x address
    }

    // Helper Functions
    function verifyNewDomain(string memory _domainName) internal view returns (bool) {
        return _domainAddress[_domainName] == address(0);
    }

    function getAuctionIDByDomain(string memory _domainName) public view returns (uint256) {
        // Return the auctionID for a particular domain name
        // If no active auction, returns [X]
    }



}