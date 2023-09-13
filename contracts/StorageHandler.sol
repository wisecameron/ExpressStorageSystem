//SPDX-License-Identifier: MIT

/*
    Author: Cameron Warnick
    https://github.com/wisecameron/ExpressStorageSystem/tree/main
*/
    
/*
    PARENT CONTRACT PERMISSIONS
    3: owner -- full permissions & can add new admins
    2: admin -- can modify, view protected entries.
    1: can view individual non-private fields
*/

pragma solidity ^0.8.0;
import './StorageSystem.sol';
import './Helper.sol';

contract StorageHandler
{
    uint256 public childrenCount;
    bool initialized;

    mapping(address => uint256) parents;
    mapping(uint256 => address) children;

    mapping(uint256 => uint256) bitIndex;
    mapping(uint256 => mapping(uint256 => uint256)) bitStructure;
    mapping(uint256 => mapping(uint256 => bool)) privateIndices;

    constructor()
    {
        parents[msg.sender] = 3;
    }

    modifier afterInit
    {
        require(initialized);
        _;
    }

    /*
        child: StorageSystem instance address
        parent: Sender contract
        bits: bit structure (will be sorted)
        origin: tx.origin (owner)

        Sets bit structure for a StorageSystem instance, 
        initializes data for this Handler.
    */
    function initialize(address child, address parentContract, uint256[] memory bits, address origin)
    external
    {
        require(parents[origin] >= 2);
        require(bits.length > 0);
        require(!initialized);

        children[0] = child;
        parents[parentContract] = 2;
        initialized = true;

        uint256 i = 0;

        for(; i < bits.length; i++)
        {
            bitStructure[0][i] = bits[i];
        }

        bitIndex[0] = bits.length;
        StorageSystem s = StorageSystem(child);
        s.set_bit_structure(origin, bits);
    }

    /*
        [Optional] ownership tracking support
    */
    function set_data_ownership( uint256 dataIndex, address user, uint256 page, address origin)
    external
    {
        require(parents[origin] > 1);
        require(page <= childrenCount);

        StorageSystem s = StorageSystem(children[page]);
        s.set_data_ownership(dataIndex, user);
    }

    /*
        Extend the system with a new abstracted mapping(uint256 => struct)
    */
    function append_new_storage_instance(address child, uint256[] memory bits, address origin)
    external
    {
        require(parents[origin] == 3);

        childrenCount += 1;

        uint256 i = 0;

        children[childrenCount] = child;

        for(; i < bits.length; i++)
        {
            bitStructure[childrenCount][i] = bits[i];
        }
        bitIndex[childrenCount] = bits.length;

        StorageSystem s = StorageSystem(child);
        s.set_bit_structure(origin, bits);
    }

    /*
        Set an entry to private
    */
    function manage_private(uint256 innerIndex, uint256 outerIndex)
    afterInit
    external
    {
        require(parents[msg.sender] >= 2);

        privateIndices[innerIndex][outerIndex] = !privateIndices[innerIndex][outerIndex];
    }

    /*
        Modify permission levels
    */
    function update_parent(address parentAddressToUpdate, uint256 permissionLevel, address origin)
    external
    {
        require(parents[origin] == 3);

        parents[parentAddressToUpdate] = permissionLevel;
    }

    /*
        modify one data field
    */
    function modify(uint256 dataIndex, uint256 valueIndex, uint256 page, uint256 newValue)
    afterInit
    external
    {
        require(parents[msg.sender] >= 2);
        require(page <= childrenCount);

        StorageSystem s = StorageSystem(children[page]);
        s.modify(dataIndex, valueIndex, newValue);
    }

    //modify multiple entries in a batch call
    function multimod(uint256 dataIndex, uint256[] memory valueIndices, uint256 page, uint256[] memory newValues)
    afterInit
    external
    {
        require(parents[msg.sender] >= 2);
        require(page <= childrenCount);

        StorageSystem s = StorageSystem(children[page]);
        s.multimod(dataIndex, valueIndices, newValues);
    }

    /*
        Create new entry.
    */
    function push(uint256 storageSystemID)
    afterInit
    external
    {
        require(parents[msg.sender] >= 2);
        require(initialized);
        require(storageSystemID <= childrenCount);
        
        StorageSystem s = StorageSystem(children[storageSystemID]);
        s.push();
    }

    /*
        Add new value to the structure.
        Include the bit count, as this value
        will be packed into a uint256 if possible.

        Can only be invoked by the owner through manual 
        direct call.
    */
    function add_entry(uint256 bits, uint256 page)
    afterInit
    external
    {
        require(parents[msg.sender] == 3);
        require(Helper.is_power_of_two_gte_eight(bits));
        require(page <= childrenCount);

        StorageSystem s = StorageSystem(children[page]);
        s.add_entry(bits);
        
        bitStructure[page][bitIndex[page]] = bits;
        bitIndex[page] += 1;
    }

    /*
        Requires advanced permissions because it displays private values.
    */
    function get_array(uint256 dataIndex, uint256 page)
    afterInit
    public view
    returns(uint256[] memory)
    {
        require(parents[msg.sender] >= 2);
        require(page <= childrenCount);

        StorageSystem s = StorageSystem(children[page]);

        return s.to_array(dataIndex);
    }

    /*
        Get individual value from storage
    */
    function get_value(uint256 dataIndex, uint256 valueIndex, uint256 page)
    afterInit
    external view
    returns(uint256)
    {
        require(parents[msg.sender] > 0);
        require(page <= childrenCount);

        if(privateIndices[page][dataIndex] && parents[msg.sender] != 3)
        {
            require(parents[msg.sender] == 2);
        }

        uint256[] memory data = get_array(dataIndex, page);
        require(data.length > valueIndex);

        return(data[valueIndex]);
    }
}