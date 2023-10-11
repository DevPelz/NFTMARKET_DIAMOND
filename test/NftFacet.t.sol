// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/Diamond.sol";
import "./helpers/DiamondUtils.sol";
import "./helpers/SigUtils.sol";
import {ERC721TOKEN} from "../contracts/facets/NFTFacet.sol";
import {NftMarketplace} from "../contracts/facets/NftMarketFacet.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {LibDiamond} from "../contracts/libraries/LibDiamond.sol";

contract DiamondDeployer is Helpers, DiamondUtils, IDiamondCut {
    using ECDSA for bytes32;
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    ERC721TOKEN nft;
    NftMarketplace nftMarket;
    NftMarketplace nftMarketDiamond;
    ERC721TOKEN nftDiamond;
    // NFT variables
    uint256 ownerPriv =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public user = vm.addr(123444);

    // struct definition
    LibDiamond.Listing listing;

    function setUp() public {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet), "Test", "TST");
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        nft = new ERC721TOKEN();
        nftMarket = new NftMarketplace();

        nftDiamond = ERC721TOKEN(address(diamond));
        nftMarketDiamond = NftMarketplace(address(diamond));

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](4);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        cut[2] = (
            FacetCut({
                facetAddress: address(nft),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("ERC721TOKEN")
            })
        );

        cut[3] = (
            FacetCut({
                facetAddress: address(nftMarket),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("NftMarketplace")
            })
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        //call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}

    function testName() public {
        string memory name = nftDiamond.name();
        assertEq(name, "Test");
    }
}
