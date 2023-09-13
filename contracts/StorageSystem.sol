//SPDX-License-Identifier: MIT

/*
    Author: Cameron Warnick
    https://github.com/wisecameron/ExpressStorageSystem/tree/main
*/

pragma solidity ^0.8.0;

import { Helper } from './Helper.sol';

contract StorageSystem
{
    //Storage
    mapping(uint256 => mapping(uint256 => uint256)) dataLong;

    //ie [8, 16, 32, ...]
    mapping(uint256 => uint256) public bitStructure;

    //[optional] ownership tracking
    mapping(uint256 => address) public structOwners;

    address private _owner;
    address private _parent;

    //bitStructure length
    uint256 public structureCount;
    
    //# of populated entries
    uint256 public index;

    //Stored to avoid recalculating this value
    uint256 public bitCount;

    bool initialized = false;

    constructor(address parent)
    {
        _owner = msg.sender;
        _parent = parent;
    }

    //no direct invocation
    modifier OnlyParent
    {
        require(msg.sender == _parent);
        _;
    }

    modifier OnlyOwner
    {
        require(msg.sender == _owner);
        _;
    }

    /*
        Init contract state
    */
    function set_bit_structure(address origin, uint256[] memory values)
    external
    OnlyParent
    {
        require(origin == _owner);
        require(!initialized);

        uint256 count = values.length;

        for(uint256 i = 0; i < count; i++)
        {
            require(Helper.is_power_of_two_gte_eight(values[i]));
            bitStructure[structureCount] = values[i];
            structureCount += 1;
            bitCount += values[i];
        }

        initialized = true;
    }

    /*
        Optional ownership support
    */
    function set_data_ownership(uint256 dataIndex, address user)
    external
    OnlyParent
    {
        require(dataIndex <= index);

        structOwners[dataIndex] = user;
    }

    /*
        Gets a raw uint256 value containing data points
        delininated by the structure map.
    */
    function get_value(uint256 i1, uint256 i2)
    external view
    OnlyParent
    returns(uint256)
    {
        return(dataLong[i1][i2]);
    }

    /*
        change the index.
    */
    function set_index(uint256 newIndex)
    external
    OnlyParent
    {
        index = newIndex;
    }

    /*
        Add a new value (marked by the amount of bits it contains)
        to the storage map.
    */
    function add_entry(uint256 addBits)
    external
    OnlyParent
    {
        require(initialized);

        bitStructure[structureCount] = addBits;
        bitCount += addBits;
        structureCount += 1;
    }

    /*
        Get the data at a given index as an array.
    */
    function to_array(uint256 dataIndex)
    public view
    OnlyParent
    returns(uint256[] memory)
    {
        uint256[] memory result = new uint256[](structureCount);

        assembly
        {
            let bitCountB := 0
            let page := 0
            let iteration := 0
            let bitStructureValue := 0
            let val := 0
            let sc := sload(structureCount.slot)

            for {} lt(iteration, sc) {iteration := add(iteration, 1)}
            {
                //get bitStructure[i]
                mstore(0x0, iteration)
                mstore(0x20, bitStructure.slot) 

                bitStructureValue := keccak256(0x0, 0x40)
                bitStructureValue := sload(bitStructureValue)

                //handle reset
                if gt(add(bitCountB, bitStructureValue), 256)
                {
                    page := add(page, 1)
                    bitCountB := 0
                }

                //get value dataLong[dataIndex][page] to slot 0, then isolate.
                mstore(0x0, dataIndex)
                mstore(0x20, dataLong.slot)
                mstore(0x20, keccak256(0x0, 0x40))
                mstore(0x0, page)
                val := shr(bitCountB, sload(keccak256(0x0, 0x40)))

                //constrict value 
                switch bitStructureValue
                case 256
                {}
                case 8 
                {
                    val := and(val, 0xFF)
                }
                case 16
                {
                    val := and(val, 0xFFFF)
                }
                case 32
                {
                    val := and(val, 0xFFFFFFFF)
                }
                case 64
                {
                    val := and(val, 0xFFFFFFFFFFFFFFFF)
                }
                case 128
                {
                    val := and(val, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                }

                //put value into result array

                mstore(0x20, add(add(result, 0x20), mul(iteration, 0x20))) //get position in array 
                mstore(mload(0x20), val) //store in result array

                bitCountB := add(bitCountB, bitStructureValue)   
            }

        }

        return result;
    }

    /*
        Modify an existing entry.
    */
    function modify(uint256 dataIndex, uint256 valueIndex, uint256 newValue)
    external
    OnlyParent
    {
        uint256[] memory values = to_array(dataIndex);

        require(valueIndex < values.length);

        uint256 bs = 0;

        //verify value is in correct bounds
        assembly
        {
            mstore(0x0, valueIndex)
            mstore(0x20, bitStructure.slot)
            bs := keccak256(0x0, 0x40)
            bs := sload(bs)

            switch bs
            case 8 
            {
                bs := 0xFF
            }
            case 16
            {
                bs := 0xFFFF
            }
            case 32
            {
                bs := 0xFFFFFFFF
            }
            case 64
            {
                bs := 0xFFFFFFFFFFFFFFFF
            }
            case 128
            {
                bs := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            }
            default
            {
                bs := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            }
        }

        require(newValue <= bs);
        require(dataIndex < index);

        values[valueIndex] = newValue;

        uint256 totalPages = 0;

        //get total pages
        assembly
        {
            let bits := 0
            let i := 0
            let flag := 0
            bs := 0

            mstore(0x20, bitStructure.slot)
            
            for {}
            lt(i, add(valueIndex, 1))
            {i := add(i, 1)}
            {
                mstore(0x0, i)
                mstore(0x0, sload(keccak256(0x0, 0x40)))

                if gt(add(bits, mload(0x0)), 256)
                {
                    totalPages := add(totalPages, 1)
                    bits := mload(0x0)
                    flag := 1
                }
                if eq(flag, 0)
                {
                    bits := add(bits, mload(0x0))
                }
                flag := 0
            }
        }

        uint256 iterator = 0;
        uint256 currentPage = 0;
        uint256 currentBit = 0;
        uint256 result = 0;
        uint256 length = values.length;
        
        //modify value
        assembly
        {
            for {}
            and(lt(iterator, length), iszero(gt(currentPage, totalPages)))
            {iterator := add(iterator, 1)}
            {
                //bitStructure[iterator]
                mstore(0x0, iterator)
                mstore(0x20, bitStructure.slot)
                bs := sload(keccak256(0x0, 0x40))

                //scratch slot now used as flag
                mstore(0x0, 0)

                if gt(add(bs, currentBit), 256 )
                {
                    currentPage := add(currentPage, 1)

                    if eq(totalPages, currentPage)
                    {
                        result := mload(add(add(values, 0x20), mul(0x20, iterator)))
                    }
                    currentBit := bs
                    mstore(0x0, 1)
                }

                if eq(mload(0x0), 0)
                {
                    if eq(currentPage, totalPages)
                    {
                        result := or(result, shl(currentBit, mload(add(add(values, 0x20), mul(0x20, iterator)))))
                    }
                    currentBit := add(currentBit, bs)
                }
                mstore(0x0, 0)

            }
        }
        dataLong[dataIndex][totalPages] = result;
    }
        
    /*
        Modify several values at the price of only one.
        Should be used over modify in all applicable cases.

        * Gas savings: only about 4% more expensive than modify()
        with a single value, significantly cheaper than chained modify()
        calls for multiple values.

        There is a signfiicant amount of room for further optimization here.
    */
    function multimod(uint256 dataIndex, uint256[] memory valueIndices, uint256[] memory newValues)
    OnlyParent
    external
    {
        uint256 valueIndicesLen = valueIndices.length;
        require(dataIndex < index);
        require(valueIndicesLen == newValues.length);
        require(valueIndicesLen > 1);        

        InsertionSort(valueIndices, newValues);

        require(valueIndices[valueIndicesLen - 1] < structureCount);

        //verify no repeats in valueIndices
        assembly
        {
            let i := 0
            let len := sub(mload(valueIndices), 1)
            
            for{}
            lt(i, len)
            {i := add(i, 1)}
            {
                if eq(mload(add(add(valueIndices, 0x20), mul(0x20, i))), mload(add(add(valueIndices, 0x40), mul(0x20, i))) )
                {
                    revert(0x0, 0x0)
                }
            }
        }

        //Ensure all values are within bitStructure[i] size constraint
        assembly
        {
            let current := 0
            let max := 0
            let i := 0

            for{}
            lt(i, valueIndicesLen)
            {i := add(i, 1)}
            {
                mstore(0x0, mload(add(add(0x20, valueIndices), mul(0x20, i))))
                mstore(0x20, bitStructure.slot)

                current := sload(keccak256(0x0, 0x40))

                switch current
                case 8
                {
                    max := 0xFF
                }
                case 16
                {
                    max := 0xFFFF  
                }
                case 32
                {
                    max := 0xFFFFFFFF
                }
                case 64
                {
                    max := 0xFFFFFFFFFFFFFFFF
                }
                case 128
                {
                    max := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                }
                case 256
                {
                    max := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                }

                if gt(mload(add(add(0x20, newValues), mul(0x20, i))), max)
                {
                    revert(0x0, 0x0)
                }
            }
        }

        //modify values in local array
        uint256 r;
        uint256 swaps = 0;

        uint256[] memory values = to_array(dataIndex);
        for(uint256 i = 0; i < valueIndicesLen; i++)
        {
            r = valueIndices[i];

            values[r] = newValues[i];
            swaps += newValues[i];
        }

        swaps /= 257;
        swaps += 1;
        uint256[] memory pages = new uint256[](swaps);
        swaps = 0;

        //get pages corresponding to values in valueIndices
        assembly
        {
            let page := 0
            let bits := 0
            let i := 0
            let bitStructureValue := 0
            let bitStructureLen := sload(structureCount.slot)
            let storePage := 0
            r := 0

            mstore(0x20, bitStructure.slot)

            for
            {}
            lt(i, bitStructureLen)
            {i := add(i, 1)}
            {
                //get bitStructure[i]
                mstore(0x0, i)
                bitStructureValue := sload(keccak256(0x0, 0x40))

                //update page, bits
                mstore(0x0, 0)
                if gt(add(bitStructureValue, bits), 256)
                {
                    page := add(page, 1)
                    bits := bitStructureValue
                    mstore(0x0, 1)
                    storePage := 0
                }
                if eq(0, mload(0x0))
                {
                    bits := add(bits, bitStructureValue)
                }

                //increase r (amount of valueIndices passed) if we are on one
                if eq(i, mload(add(add(0x20, valueIndices), mul(r, 0x20))))
                {
                    //if the page for this valueindex has not been stored, store it.
                    if eq(storePage, 0)
                    {
                        mstore(add(add(0x20, pages), mul(swaps, 0x20)), page)
                        storePage := 1
                        swaps := add(swaps, 1)
                    }

                    r := add(r, 1)

                }
            }
        }

        //dataLong[dataIndex][0] = swaps;
        //return;

        uint256 len = values.length;
        uint256 currentBit;
        uint256 nValue; 
        uint256 currentPage;

        swaps = 0; //total new pages stored
        r = 0; //total valueIndices values passed

        nValue = 0;

        for(uint256 i = 0; i < len; i++)
        {
            if(swaps == pages.length) return;

            //reset case
            if(currentBit + bitStructure[i] > 256)
            {
                //if the current page is a page with values we need
                if(currentPage == pages[swaps])
                {
                    //give it the nValue we have been making
                    dataLong[dataIndex][pages[swaps]] = nValue;
                    swaps += 1;
                }

                //reset nValue
                nValue = values[i];
                currentPage += 1;
                currentBit = bitStructure[i];
            }
            else
            {
                //construct nValue
                nValue |= values[i] << currentBit;
                currentBit += bitStructure[i];
            }

            if((i + 1) == len)
            {
                //if currentPage needs to be replaced
                dataLong[dataIndex][pages[swaps]] = nValue;
            }

        }
        return;
    }

    function InsertionSort(uint256[] memory indices, uint256[] memory values)
    internal pure
    returns(uint256[] memory)
    {
        require(indices.length == values.length);

        uint256 n = indices.length;

        for(uint256 i = 1; i < n; i++)
        {
            uint256 j = i;
            while(j > 0 && indices[j - 1] > indices[j])
            {
                //swap indices and values
                uint256 t = indices[j - 1];
                indices[j - 1] = indices[j];
                indices[j] = t;

                t = values[j - 1];
                values[j - 1] = values[j];
                values[j] = t;

                j-=1;
            }
        }

        return indices;
    }

    /*
        Create a new entry
    */
    function push()
    external
    OnlyParent
    {

        index += 1;
    }
    
    /*
        View the bit structure for this storage contract
    */
    function bitStructureVals()
    public view
    returns(uint256[] memory)
    {
        uint256[] memory j = new uint256[](structureCount);

        for(uint256 z = 0; z < structureCount; z++)
        {
            j[z] = bitStructure[z];
        }

        return j;
    }
}