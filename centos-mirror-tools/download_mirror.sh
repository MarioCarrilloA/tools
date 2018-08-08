#!/bin/bash -e
echo "--------------------------------------------------------------"

echo "WARNING: this script HAS TO access internet (http/https/ftp),"
echo "so please make sure your network working properly!!"

mkdir -p ./logs

rpm_downloader="./dl_rpms.sh"
if [ ! -e $rpm_downloader ];then
    echo "ERROR: $rpm_downloader does NOT exist!!"
    exit -1
fi

#download RPMs/SRPMs from 3rd_party websites (not CentOS repos) by "wget"
echo "step #1: start downloading RPMs/SRPMs from 3rd-party websites..."
if [ ! -e ./rpms_from_3rd_parties.lst ];then
    echo "ERROR: ./rpms_from_3rd_parties.lst does NOT exist!!"
    exit -1
fi

# Restore StarlingX_3rd repos from backup
REPO_SOURCE_DIR=/localdisk/yum.repos.d
REPO_DIR=/etc/yum.repos.d
if [ -d $REPO_SOURCE_DIR ] && [ -d $REPO_DIR ]; then
    \cp -f $REPO_SOURCE_DIR/*.repo $REPO_DIR/
fi

$rpm_downloader ./rpms_from_3rd_parties.lst L1 3rd | tee ./logs/log_download_rpms_from_3rd_party.txt
if [ $? != 0 ];then
    echo "ERROR: something wrong with downloading, please check the log!!"
fi

# download RPMs/SRPMs from 3rd_party repos by "yumdownloader"
$rpm_downloader ./rpms_from_centos_3rd_parties.lst L1 3rd-centos | tee ./logs/log_download_rpms_from_centos_3rd_parties_L1.txt

# deleting the StarlingX_3rd to avoid pull centos packages from the 3rd Repo.
\rm -f $REPO_DIR/StarlingX_3rd*.repo

echo "step #2: start 1st round of downloading RPMs and SRPMs with L1 match criteria..."
#download RPMs/SRPMs from CentOS repos by "yumdownloader"
if [ ! -e ./rpms_from_centos_repo.lst ];then
    echo "ERROR: ./rpms_from_centos_repo.lst does NOT exist!!"
    exit -1
fi

$rpm_downloader ./rpms_from_centos_repo.lst L1 centos | tee ./logs/log_download_rpms_from_centos_L1.txt
if [ $? == 0 ]; then
    echo "finish 1st round of RPM downloading successfully!"
    if [ -e "./output/centos_rpms_missing_L1.txt" ]; then
        missing_num=`wc -l ./output/centos_rpms_missing_L1.txt | cut -d " " -f1-1`
        if [ "$missing_num" != "0" ];then
            echo "ERROR:  -------RPMs missing $missing_num in yumdownloader with L1 match ---------------"
        fi
        #echo "start 2nd round of downloading Binary RPMs with L2 match criteria..."
        #$rpm_downloader ./output/centos_rpms_missing_L1.txt L2 centos | tee ./logs/log_download_rpms_from_centos_L2.txt
        #if [ $? == 0 ]; then
        #    echo "finish 2nd round of RPM downloading successfully!"
        #    if [ -e "./output/rpms_missing_L2.txt" ]; then
        #        echo "WARNING: we're still missing RPMs listed in ./rpms_missing_L2.txt !"
        #    fi
        #fi
    fi

    if [ -e "./output/centos_srpms_missing_L1.txt" ]; then
        missing_num=`wc -l ./output/centos_srpms_missing_L1.txt | cut -d " " -f1-1`
        if [ "$missing_num" != "0" ];then
            echo "ERROR: --------- SRPMs missing $missing_num in yumdownloader with L1 match ---------------"
        fi
        #echo "start 2nd round of downloading Source RPMs with L2 match criteria..."
        #$rpm_downloader ./output/centos_srpms_missing_L1.txt L2 centos | tee ./logs/log_download_srpms_from_centos_L2.txt
        #if [ $? == 0 ]; then
        #    echo "finish 2nd round of SRPM downloading successfully!"
        #    if [ -e "./srpms_missing_L2.txt" ]; then
        #        echo "WARNING: we're still missing SRPMs listed in ./rpms_missing_L2.txt !"
        #    fi
        #fi
    fi
else
    echo "finish 1st round with failures!"
fi

## verify all RPMs SRPMs we download for the GPG keys
find ./output -type f -name "*.rpm" | xargs rpm -K | grep -i "MISSING KEYS" > ./rpm-gpg-key-missing.txt

# remove all i686.rpms to avoid pollute the chroot dep chain
find ./output -name "*.i686.rpm" | tee ./output/all_i686.txt
find ./output -name "*.i686.rpm" | xargs rm -f

line1=`wc -l rpms_from_3rd_parties.lst | cut -d " " -f1-1`
line2=`wc -l rpms_from_centos_repo.lst | cut -d " " -f1-1`
line3=`wc -l rpms_from_centos_3rd_parties.lst | cut -d " " -f1-1`
let total_line=$line1+$line2+$line3
echo "We expect to download $total_line RPMs."
num_of_downloaded_rpms=`find ./output -type f -name "*.rpm" | wc -l | cut -d" " -f1-1`
echo "There are $num_of_downloaded_rpms RPMs in output directory."
if [ "$total_line" != "$num_of_downloaded_rpms" ]; then
    echo "WARNING: Not the same number of RPMs in output as RPMs expected to be downloaded, need to check outputs and logs."
fi

# change "./output" and sub-folders to 751 (cgcs) group
chown  751:751 -R ./output

other_downloader="./dl_other_from_centos_repo.sh"

if [ ! -e ./other_downloads.lst ];then
    echo "ERROR: ./other_downloads.lst does not exist!"
    exit -1
fi

echo "step #3: start downloading other files ..." 
$other_downloader ./other_downloads.lst ./output/stx-r1/CentOS/pike/Binary/ | tee ./logs/log_download_other_files_centos.txt
if [ $? == 0 ];then
    echo "step #3: done successfully"
fi

# StarlingX requires a group of source code pakages, in this section
# they will be downloaded.
echo "step #4: start downloading tarball compressed files"
./dl_tarball.sh

echo "IMPORTANT: The following 3 files are just bootstrap versions. Based"
echo "on them, the workable images for StarlingX could be generated by"
echo "running \"update-pxe-network-installer\" command after \"build-iso\""
echo "    - out/stx-r1/CentOS/pike/Binary/LiveOS/squashfs.img"
echo "    - out/stx-r1/CentOS/pike/Binary/images/pxeboot/initrd.img"
echo "    - out/stx-r1/CentOS/pike/Binary/images/pxeboot/vmlinuz"

