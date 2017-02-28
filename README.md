# Dup2HardLink

## What does it do

Compare two directories, find the duplicate files with same relative path and
same hash checksum, and for each pair of them, replace one with a hard link
targeting to the other so that they sharing the same inode.

The main purpose is to save hard-disk space.

## Warning

If you don't know what is a hard link, do not use this script, at least the file
deletion and hard-link creation part of its features. It's safe to only use the
analysis feature. To learn about hard links, you can refer to [this
document](http://www.linfo.org/hard_link.html) and
[Wikipedia](https://en.wikipedia.org/wiki/Hard_link).

If you know what this script does, data backup is still recommended.

## Example

```console
$ Dup2HardLink.bat folder1 folder2
[20:18:28.29] Listing the 1st directory
[20:18:28.40] Selecting common files
[20:18:28.52] Selecting same-size files
[20:18:28.65] Creating hash checksums for files in the 1st directory
[20:18:43.84] Checking checksums against files in the 2nd directory
sha1sum: WARNING: 13 of 233 computed checksums did NOT match
[20:18:44.56] Statistics:
        ┌───────────────┬─────────────┬────────────────┐
        │               │ Total files │     Total size │
        ├───────────────┼─────────────┼────────────────┤
        │ Directory 1   │         247 │     14,553,566 │
        │ Directory 2   │         247 │     14,636,638 │
        ├───────────────┼─────────────┼────────────────┤
        │ Common files  │         247 │                │
        │ Same sized    │         233 │                │
        │ Hash matching │         220 │      5,733,289 │
        └───────────────┴─────────────┴────────────────┘
```
