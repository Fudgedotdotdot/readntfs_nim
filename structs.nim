type
  BootSector* {.packed.} = object
    jump*: array[3, uint8]
    name*: array[8, char]
    bytesPerSector*: uint16
    sectorsPerCluster*: uint8
    reservedSectors*: uint16
    unused0: array[3, uint8]
    unused1: uint16
    media*: uint8
    unused2: uint16
    sectorsPerTrack*: uint16
    headsPerCylinder*: uint16
    hiddenSectors*: uint32
    unused3: uint32
    unused4: uint32
    totalSectors*: uint64
    mftStart*: uint64
    mftMirrorStart*: uint64
    clustersPerFileRecord*: uint32
    clustersPerIndexBlock*: uint32
    serialNumber*: uint64
    checksum*: uint32
    bootloader*: array[426, uint8]
    bootSignature*: uint16

type
  FileRecordHeader* {.packed.} = object
    magic*: uint32
    offsetOfFixUp*: uint16
    sizeOfFixUp*: uint16
    LSN*: uint64
    seqNo*: uint16
    hardlinks*: uint16
    offsetOfAttr*: uint16
    flags*: uint16
    realSize*: uint32
    allocSize*: uint32
    refToBase*: uint64
    nextAttrId*: uint16
    align*: uint16
    recordNo*: uint32

type
  AttributeHeaderCommon* {.packed.} = object
    attributeType*: uint32
    totalSize*: uint32
    isResident*: uint8
    nameLength*: uint8
    nameOffset*: uint16
    flags*: uint16
    id*: uint16

  AttributeHeaderResident* {.packed.} = object
    header*: AttributeHeaderCommon
    attrSize*: uint32
    attrOffset*: uint16
    indexedFlag*: uint8
    padding*: uint8

  AttributeHeaderNonResident* {.packed.} = object
    header*: AttributeHeaderCommon
    startVCN*: uint64
    lastVCN*: uint64
    dataRunOffset*: uint16
    compUnitSize*: uint16
    padding*: uint32
    allocSize*: uint64
    realSize*: uint64
    iniSize*: uint64

type
  FileNameAttributeHeader* {.packed.} = object
    header*: AttributeHeaderResident
    parentRecordNumber* {.bitsize: 48.}: int64
    sequenceNumber* {.bitsize: 16.}: int64
    creationTime*: int64
    modificationTime*: int64
    metadataModificationTime*: int64
    readTime*: int64
    allocatedSize*: int64
    realSize*: int64
    flags*: uint32
    reparse*: uint32
    fileNameLength*: uint8
    namespaceType*: uint8
    fileName*: array[0..0, uint16]  # WCHAR → uint16 in Nim
#[
type
  FileRecordHeader* {.packed.} = object
    magic*: DWORD                # "FILE"
    offsetOfFixUp*: WORD            # Offset of Update Sequence
    sizeOfFixUp*: WORD              # Size in words of Update Sequence Number & Array
    LSN*: ULONGLONG              # $LogFile Sequence Number
    seqNo*: WORD                 # Sequence number
    hardlinks*: WORD             # Hard link count
    offsetOfAttr*: WORD          # Offset of the first Attribute
    flags*: WORD                 # Flags
    realSize*: DWORD             # Real size of the FILE record
    allocSize*: DWORD            # Allocated size of the FILE record
    refToBase*: ULONGLONG        # File reference to the base FILE record
    nextAttrId*: WORD            # Next Attribute Id
    align*: WORD                 # Align to 4-byte boundary
    recordNo*: uint32            # Number of this MFT Record


type
  # https://github.com/PowerShellMafia/PowerSploit/blob/master/Exfiltration/NTFSParser/NTFSParserDLL/NTFS_DataType.h
  AttributeHeaderCommon* {.packed.} = object
    attributeType*: DWORD              # Attribute Type
    totalSize*: DWORD         # Length (including this header)
    isResident*: BYTE        # 0 - resident, 1 - non-resident
    nameLength*: BYTE         # Name length in words
    nameOffset*: WORD         # Offset to the name
    flags*: WORD              # Flags
    id*: WORD                 # Attribute ID

  AttributeHeaderResident* {.packed.} = object
    header*: AttributeHeaderCommon
    attrSize*: DWORD             # Length of the attribute body
    attrOffset*: WORD            # Offset to the Attribute
    indexedFlag*: BYTE           # Indexed flag
    padding*: BYTE               # Padding

  AttributeHeaderNonResident* {.packed.} = object
    header*: AttributeHeaderCommon  # Common data structure
    startVCN*: ULONGLONG         # Starting VCN
    lastVCN*: ULONGLONG          # Last VCN
    dataRunOffset*: WORD         # Offset to the Data Runs
    compUnitSize*: WORD          # Compression unit size
    padding*: DWORD              # Padding
    allocSize*: ULONGLONG        # Allocated size of the attribute
    realSize*: ULONGLONG         # Real size of the attribute
    iniSize*: ULONGLONG          # Initialized data size of the stream


type
  FileNameAttributeHeader* {.packed.} = object
    header*: AttributeHeaderResident
    parentRecordNumber* {.bitsize: 48.}: LONGLONG
    sequenceNumber* {.bitsize: 16.}: LONGLONG
    creationTime*: LONGLONG
    modificationTime*: LONGLONG
    metadataModificationTime*: LONGLONG
    readTime*: LONGLONG
    allocatedSize*: LONGLONG
    realSize*: LONGLONG
    flags*: DWORD
    reparse*: DWORD
    fileNameLength*: BYTE
    namespaceType*: BYTE
    fileName*: array[0..0, WCHAR]
]#
