import strutils, strformat, sequtils, bitops, std/cmdline, os
import tables
import structs
import math
import winim/lean
import ptr_math


type
  FileObj = object
    parentRecord: int
    filename: string
    dataRuns: seq[tuple[offset: int, length: int]]


proc convertLittleEndian(buf: openArray[byte]): int = 
  for index, value in buf:
    result = result or (value.int shl (index * 8))


proc parseDataRuns(fileResidentHeader: ptr AttributeHeaderNonResident, clusterSize: int, record: var FileObj) =
  var 
      ptrDataRun = cast[ptr byte](fileResidentHeader) + fileResidentHeader.dataRunOffset.int
      dataRunOffset: int = 0

  while true:
    if ptrDataRun[] == 0:
      break
    var 
      runHeaderOffset: int = int(ptrDataRun[] shr 4)
      runHeaderLength: int = int(ptrDataRun[] and 0xF)
      dataRunLength: int = 0
      currentDataRunOffset: int = 0
      lengthBuf = newSeq[byte](runHeaderLength)
      offsetBuf = newSeq[byte](runHeaderOffset)

    if runHeaderOffset == 0: # explicitly treating sparse record
      ptrDataRun += runHeaderLength + runHeaderOffset + 1
      continue
    else:
      copyMem(lengthBuf[0].addr, ptrDataRun + 1, runHeaderLength)
      copyMem(offsetBuf[0].addr, ptrDataRun + 1 + runHeaderLength, runHeaderOffset)

      dataRunLength = convertLittleEndian(lengthBuf)
      currentDataRunOffset = convertLittleEndian(offsetBuf)

      if (currentDataRunOffset shr (offsetBuf.len * 8 - 1)) == 1:
        var signMask = toMask[int](0..countLeadingZeroBits(currentDataRunOffset) - 1) shl (offsetBuf.len * 8)
        currentDataRunOffset.setmask(signMask)

      dataRunOffset += currentDataRunOffset
      record.dataRuns.add((offset: dataRunOffset * clusterSize, length: dataRunLength * clusterSize))

    ptrDataRun += runHeaderLength + runHeaderOffset + 1


proc parseAttributes(mftFile: var array[1024, byte], offsetOfAttr: int, recordNo: int, clusterSize: int, record: var FileObj) = 
  var attribute = cast[ptr AttributeHeaderCommon](mftFile[0].addr + offsetOfAttr)
  while true:
    if attribute.attributeType == fromHex[uint32]("0x30"):
      var filenameHeader = cast[ptr FileNameAttributeHeader](attribute)
      if attribute.isResident == 0 and filenameHeader.namespaceType != 2:
        var filename = newWString(filenameHeader.fileNameLength)
        copyMem(&filename, cast[ptr byte](filenameHeader.fileName.addr), filename.len * 2)
        record.parentRecord = filenameHeader.parentRecordNumber
        record.filename = $filename

    elif attribute.attributeType == fromHex[uint32]("0x80"):
      if attribute.isResident == 1:
        let fileResidentHeader = cast[ptr AttributeHeaderNonResident](attribute)
        parseDataRuns(fileResidentHeader, clusterSize, record)

    elif attribute.attributeType == fromHex[uint32]("0xFFFFFFFF"):
      break

    attribute = cast[ptr AttributeHeaderCommon](cast[ptr byte](attribute) + attribute.totalSize.int) 


proc performFixUp(buf: var array[1024, byte], offsetFixUp: int, sizeFixUp: int, recordSize: int, sectorSize: int) = 
  var
    sectorIdx: int = 0
    usa: seq[byte] = buf[offsetFixUp + 2 ..< offsetFixUp + 2 + sizeFixUp * 2]

  for i in 0..<sizeFixUp:
    if sectorIdx + sectorSize > buf.len:
      break
    buf[sectorIdx + sectorSize - 2] = usa[i]
    buf[sectorIdx + sectorSize - 1] = usa[i+1]
    sectorIdx += sectorSize


proc readFirstBytes(drive: var File, record: FileObj): string =
  if len(record.dataRuns) == 0:
    echo "[!] File is resident, not parsing resident files at the moment"
    return ""
  var totalLength = record.dataRuns.mapit(it.length).foldl(a + b)
  var fileContent = newSeq[byte](totalLength)
  var fileContentOffset: int = 0
  for run in record.dataRuns:
    setFilePos(drive, run.offset)
    discard readBytes(drive, fileContent, fileContentOffset, run.length)
    fileContentOffset += run.length
  return fileContent.mapit(chr(it)).join("")


proc main(filenamePath: string, outputFile: string): bool = 
  let driveRoot: string = "\\\\.\\C:"
  var drive: File
  if not open(drive, driveRoot):
    echo "[-] OpenFile failed"
    return false
  defer: drive.close()

  var bootSector: BootSector
  setFilePos(drive, 0)
  discard readBuffer(drive, bootSector.addr, sizeof(BootSector))
  var sectorsPerCluster: int
  if bootSector.sectorsPerCluster > 0 or bootSector.sectorsPerCluster <= 128:
    sectorsPerCluster = bootSector.sectorsPerCluster.int
  elif bootSector.sectorsPerCluster >= 244 or bootSector.sectorsPerCluster <= 255:
    sectorsPerCluster = 2 ^ abs(sectorsPerCluster.int)
  else:
    echo fmt"Unknown value for sectorsPerCluster: {bootSector.sectorsPerCluster}"
    return false
  echo "[*] SectorsPerCluster: ", sectorsPerCluster
  echo "[*] BytesPerSector: ", bootSector.bytesPerSector
  let mftOffset = bootSector.bytesPerSector.int * sectorsPerCluster * bootSector.mftStart.int64
  echo "[*] MFT Offset: ", mftOffset
  let recordSize = 1024
  echo "[*] RecordSize: ", recordSize
  let clusterSize = int(bootSector.bytesPerSector.int * sectorsPerCluster)
  echo "[*] ClusterSize: ", clusterSize

  var 
    mftFile: array[1024, byte]
    fileRecord: ptr FileRecordHeader
    records = initTable[uint32, FileObj]()

  setFilePos(drive, mftOffset.int)
  discard readBuffer(drive, mftFile.addr, 1024)
  fileRecord = cast[ptr FileRecordHeader](mftFile.addr)
  doAssert fileRecord.magic.toHex() == "454C4946"

  records[fileRecord.recordNo] = FileObj()

  performFixUp(mftFile, fileRecord.offsetOfFixUp.int, fileRecord.sizeOfFixUp.int, recordSize, bootSector.bytesPerSector.int)
  parseAttributes(mftFile, fileRecord.offsetOfAttr.int, fileRecord.recordNo.int, clusterSize, records[fileRecord.recordNo])

  for run in records[0'u32].dataRuns:
    var dataRunBuf = newSeq[byte](run.length)
    var mftRecord: array[1024, byte]
    echo fmt"[+] Parsing 0x{toHex(int(run.length / clusterSize))} clusters @ LCN 0x{toHex(run.offset)}"
    setFilePos(drive, run.offset)
    discard readBuffer(drive, dataRunBuf[0].addr, run.length)

    for i in 0..<run.length div recordSize:
      var recordOffset = i * recordSize
      copyMem(mftRecord[0].addr, dataRunBuf[recordOffset].addr, recordSize)
      fileRecord = cast[ptr FileRecordHeader](mftRecord.addr)
      if fileRecord.magic.toHex() != "454C4946":
        continue

      records[fileRecord.recordNo] = FileObj()
      performFixUp(mftRecord, fileRecord.offsetOfFixUp.int, fileRecord.sizeOfFixUp.int, recordSize, bootSector.bytesPerSector.int)
      parseAttributes(mftRecord, fileRecord.offsetOfAttr.int, fileRecord.recordNo.int, clusterSize, records[fileRecord.recordNo])

  var
    currentRootId = 5
    fileContent: string
  let 
    path: string = filenamePath
    filename: string = path.split(r"\")[^1]
  for inode in path.split(r"\")[1..^1]:
    for recordid, value in records:
      if value.filename == inode and value.parentRecord == currentRootId:
        currentRootId = recordid.int
        if filename == inode:
          fileContent = readFirstBytes(drive, value)
        break

  echo fmt"[+] Writing file contents"
  writeFile(outputFile, fileContent)

when isMainModule:
  if paramCount() != 2:
    quit(fmt"[+] Usage: {getAppFilename()} <file to read> <output file>")
  echo fmt"[+] Reading {paramStr(1)}"
  discard main(paramStr(1), paramStr(2))
