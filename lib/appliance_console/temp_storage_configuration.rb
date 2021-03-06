require_relative "logging"

module ApplianceConsole
  class TempStorageConfiguration
    TEMP_DISK_FILESYSTEM_TYPE = "ext4".freeze
    TEMP_DISK_MOUNT_POINT     = Pathname.new("/var/www/miq_tmp").freeze
    TEMP_DISK_MOUNT_OPTS      = "rw,noatime,data=writeback,barrier=0,nobh".freeze

    attr_reader :disk

    include ApplianceConsole::Logging

    def process_menus
      say("#{I18n.t("advanced_settings.tmp_config")}\n\n")
      disk = ask_questions
      if disk && are_you_sure?("configure #{disk.path} as temp storage")
        say("Configuring #{disk.path} as temp storage...")
        add_temp_disk(disk)
        say("Done.")
        press_any_key
      else
        say("Canceled...")
        press_any_key
      end
    end

    def ask_questions
      ask_for_disk("temp storage disk")
    end

    def add_temp_disk(disk)
      log_and_feedback(__method__) do
        partition = create_partition_to_fill_disk(disk)
        format_partition(partition)
        mount_temp_disk(partition)
        update_fstab(partition)
      end
    end

    def format_partition(partition)
      LinuxAdmin.run!("mke2fs -t #{TEMP_DISK_FILESYSTEM_TYPE} #{partition.path}")
    end

    def mount_temp_disk(partition)
      # TODO: should this be moved into LinuxAdmin?
      FileUtils.rm_rf(TEMP_DISK_MOUNT_POINT)
      FileUtils.mkdir_p(TEMP_DISK_MOUNT_POINT)
      LinuxAdmin.run!("mount",
                      :params => {
                        "-t"  => TEMP_DISK_FILESYSTEM_TYPE,
                        "-o"  => TEMP_DISK_MOUNT_OPTS,
                        nil   => [partition.path, TEMP_DISK_MOUNT_POINT]
                      }
      )
    end

    def update_fstab(partition)
      fstab = LinuxAdmin::FSTab.instance
      return if fstab.entries.find { |e| e.mount_point == TEMP_DISK_MOUNT_POINT }

      entry = LinuxAdmin::FSTabEntry.new(
        :device        => partition.path,
        :mount_point   => TEMP_DISK_MOUNT_POINT,
        :fs_type       => TEMP_DISK_FILESYSTEM_TYPE,
        :mount_options => TEMP_DISK_MOUNT_OPTS,
        :dumpable      => 0,
        :fsck_order    => 0
      )

      fstab.entries << entry
      fstab.write!  # Test this more, whitespace is removed
    end

    # FIXME: Copied from InternalDatabaseConfiguration - remove both when LinuxAdmin updated
    def create_partition_to_fill_disk(disk)
      # @disk.create_partition('primary', '100%')
      disk.create_partition_table # LinuxAdmin::Disk.create_partition has this already...
      LinuxAdmin.run!("parted -s #{disk.path} mkpart primary 0% 100%")

      # FIXME: Refetch the disk after creating the partition
      disk = LinuxAdmin::Disk.local.select { |d| d.path == disk.path }.first
      disk.partitions.first
    end
  end # class TempStorageConfiguration
end # module ApplianceConsole
