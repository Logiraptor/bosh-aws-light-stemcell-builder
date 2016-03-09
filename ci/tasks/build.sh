#!/usr/bin/env bash

set -ex -o pipefail

my_dir="$( cd $(dirname $0) && pwd )"
release_dir="$( cd ${my_dir} && cd ../.. && pwd )"

source ${release_dir}/ci/tasks/utils.sh

: ${ami_description:?}
: ${ami_virtualization_type:?}
: ${ami_visibility:?}
: ${us_ami_region:?}
: ${us_ami_access_key:?}
: ${us_ami_secret_key:?}
: ${us_ami_bucket_name:?}
: ${us_ami_destinations:?}
: ${cn_ami_region:?}
: ${cn_ami_access_key:?}
: ${cn_ami_secret_key:?}
: ${cn_ami_bucket_name:?}

stemcell_path=${PWD}/input-stemcell/*.tgz
output_path=${PWD}/light-stemcell/

echo "Building light stemcell"

export CONFIG_PATH=${PWD}/config.json

cat > $CONFIG_PATH << EOF
{
  "ami_configuration": {
    "description":          "$ami_description",
    "virtualization_type":  "$ami_virtualization_type",
    "visibility":           "$ami_visibility"
  },
  "ami_regions": [
    {
      "name":               "$us_ami_region",
      "credentials": {
        "access_key":       "$us_ami_access_key",
        "secret_key":       "$us_ami_secret_key"
      },
      "bucket_name":        "$us_ami_bucket_name",
      "destinations":       $us_ami_destinations
    },
    {
      "name":               "$cn_ami_region",
      "credentials": {
        "access_key":       "$cn_ami_access_key",
        "secret_key":       "$cn_ami_secret_key"
      },
      "bucket_name":        "$cn_ami_bucket_name"
    }
  ]
}
EOF

echo "Configuration:"
cat $CONFIG_PATH

extracted_stemcell_dir=${PWD}/extracted-stemcell
mkdir -p ${extracted_stemcell_dir}
tar -C ${extracted_stemcell_dir} -xf ${stemcell_path}
tar -xf ${extracted_stemcell_dir}/image

original_stemcell_name="$(basename ${stemcell_path})"
light_stemcell_name="light-${original_stemcell_name}"

if [ "${ami_virtualization_type}" = "hvm" ]; then
  light_stemcell_name="${light_stemcell_name/xen/xen-hvm}"
fi

# image format can be raw or stream optimized vmdk
stemcell_image="$(echo ${PWD}/root.*)"
stemcell_manifest=${extracted_stemcell_dir}/stemcell.MF
manifest_contents="$(cat ${stemcell_manifest})"

disk_regex="disk: ([0-9]+)"
format_regex="disk_format: ([a-z]+)"

[[ "${manifest_contents}" =~ ${disk_regex} ]]
disk_size_gb=$(mb_to_gb "${BASH_REMATCH[1]}")

[[ "${manifest_contents}" =~ ${format_regex} ]]
disk_format="${BASH_REMATCH[1]}"

pushd ${release_dir} > /dev/null
  . .envrc
  # Make sure we've closed the manifest file before writing to it
  go run src/light-stemcell-builder/main.go \
    -c $CONFIG_PATH \
    --image ${stemcell_image} \
    --format ${disk_format} \
    --volume-size ${disk_size_gb} \
    --manifest ${stemcell_manifest} \
    | tee tmp-manifest

  mv tmp-manifest ${stemcell_manifest}

popd

pushd ${extracted_stemcell_dir}
  > image
  # the bosh cli sees the stemcell as invalid if tar contents have leading ./
  tar -czf ${output_path}/${light_stemcell_name} *
popd
tar -tf ${output_path}/${light_stemcell_name}
