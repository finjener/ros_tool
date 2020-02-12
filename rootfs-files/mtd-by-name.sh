#!/bin/sh -e
# mtd-by-name link the mtdblock to name
# radxa.com, thanks to naobsd
rm -rf /dev/block/mtd/by-name/
mkdir -p /dev/block/mtd/by-name
for i in `ls -d /sys/class/mtd/mtd*[0-9]`; do
    name=`cat $i/name`
    tmp="`echo $i | sed -e 's/mtd/mtdblock/g'`"
    dev="`echo $tmp |sed -e 's/\/sys\/class\/mtdblock/\/dev/g'`"
    ln -s $dev /dev/block/mtd/by-name/$name
done
