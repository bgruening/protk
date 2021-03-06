require 'protk/constants'
require 'protk/randomize'
require 'uri'
require 'digest/md5'
require 'net/ftp'
require 'net/ftp/list'
require 'bio'
require 'tempfile'
require 'pp'
require 'set'

dbname=ARGV[0]

# Load database spec file
#
$genv=Constants.new()
dbdir="#{$genv.protein_database_root}/#{dbname}"

dbspec_file="#{dbdir}/.protkdb.yaml"
dbspec=YAML.load_file "#{dbspec_file}"

format = dbspec[:format]!=nil ? dbspec[:format] : "fasta"

# Output database filename
#
db_filename="#{dbdir}/current.#{format}"

#####################
# Utility Functions #
#####################


def check_ftp_release_notes(release_notes)
  rn_uri = URI.parse(release_notes)

  rn_path="#{$genv.database_downloads}/#{rn_uri.host}/#{rn_uri.path}"

  update_needed=false

  host=rn_uri.host
  Net::FTP.open(host) do |ftp|

    ftp.login
    rn_dir=Pathname.new(rn_uri.path).dirname.to_s
    rn_file=Pathname.new(rn_uri.path).basename.to_s
    ftp.chdir(rn_dir)

    ftp.passive=true


    p "Checking release notes"
    
    # Is the last path component a wildcard expression (we only allow *)
    # If so we need to find the file with the most recent modification time
    #
    if ( rn_file =~ /\*/)
      entries=ftp.list(rn_file)
      p entries
      latest_file=nil
      latest_file_mtime=nil
      entries.each do |dir_entry|
        info=Net::FTP::List.parse(dir_entry)
        if ( info.file? )
          latest_file_mtime = info.mtime if ( latest_file_mtime ==nil )
          latest_file = info.basename if ( latest_file_mtime ==nil )
          
          if ( info.mtime <=> latest_file_mtime ) #entry's mtime is later
            latest_file_mtime=info.mtime
            latest_file=info.basename
          end

        end        
      end
        
      throw "No release notes found" if ( latest_file ==nil)

      rn_file=latest_file

      # Adjust the rn_path to be the path of the latest file
      #
      rn_path="#{Pathname.new(rn_path).dirname}/#{latest_file}"

    end

    # Hash existing release notes data if it exists
    #
    existing_digest=nil
    existing_digest=Digest::MD5.hexdigest(File.read(rn_path))  if  Pathname.new(rn_path).exist? 



    rn_data=""
    dl_file=Tempfile.new("rn_file")
        
    ftp.getbinaryfile(rn_file,dl_file.path) { |data|  rn_data << data }

    rn_digest=Digest::MD5.hexdigest(rn_data)

    p "Done Downloading release notes #{ftp} #{rn_file} to #{dl_file.path} #{ftp.pwd}"

    throw "No release notes data at #{release_notes}" unless rn_digest!=nil

    # Update release notes data
    case
    when ( existing_digest != rn_digest )
      FileUtils.mkpath(Pathname.new(rn_path).dirname.to_s)
      File.open(rn_path, "w") {|file| file.puts(rn_data) }
      update_needed = true
    else
      p "Release notes are up to date"
    end 
  end
  update_needed
end

def download_ftp_file(ftp,file_name,dest_dir)
  dest_path="#{dest_dir}/#{file_name}"
  
  download_size=ftp.size(file_name)
  mod_time=ftp.mtime(file_name,true)



  percent_size=download_size/100
  i=1
  pc_complete=0
  last_time=Time.new
  p "Downloading #{file_name}"
  ftp.passive=true
  
  ftp.getbinaryfile(file_name,dest_path,1024) { |data| 
    
    progress=i*1024
    if ( pc_complete < progress.divmod(percent_size)[0] && ( Time.new - last_time) > 10 )
      pc_complete=progress.divmod(percent_size)[0]
      p "Downloading #{file_name} #{pc_complete} percent complete"
      last_time=Time.new
    end
    i=i+1
  }
  
end

def download_ftp_source(source)

  data_uri = URI.parse(source)

  data_path="#{$genv.database_downloads}/#{data_uri.host}/#{data_uri.path}"
  # Make sure our destination dir is available
  #
  FileUtils.mkpath(Pathname.new(data_path).dirname.to_s)



  Net::FTP.open(data_uri.host) do |ftp|
    p "Connected to #{data_uri.host}"
    ftp.login
    
    ftp.chdir(Pathname.new(data_uri.path).dirname.to_s)

    last_path_component=Pathname.new(data_uri.path).basename.to_s
    
    case 
    when last_path_component=~/\*/  # A wildcard match. Need to download them all
      p "Getting directory listing for #{last_path_component}"
      ftp.passive=true
      matching_items=ftp.list(last_path_component)
      
      PP.pp(matching_items)
      
      matching_items.each do |dir_entry|
        info=Net::FTP::List.parse(dir_entry)
        download_ftp_file(ftp,info.basename,Pathname.new(data_path).dirname)
      end
      
    else # Just one file to download
      download_ftp_file(ftp,last_path_component,Pathname.new(data_path).dirname)
    end

  end

end

  
def archive_fasta_file(filename)
  if ( Pathname.new(filename).exist? )
    mt=File.new(filename).mtime
    timestamp="#{mt.year}_#{mt.month}_#{mt.day}"
    archive_filename="#{filename.gsub(/.fasta$/,'')}_#{timestamp}.fasta"
    p "Moving old database to #{archive_filename}"
    FileUtils.mv(filename,archive_filename)
  end
end

def cleanup_file(filename)
  if  (File.exist? filename  )
    archive_filename="#{filename}.tmp"
    p "Cleaning up #{filename}"
    FileUtils.mv(filename,archive_filename,:force=>true)
  end
end

#####################
# Source Files      #
#####################

def file_source(raw_source)
  full_path=raw_source
  full_path = "#{$genv.protein_database_root}/#{raw_source}" unless ( raw_source =~ /^\//) # relative paths should be relative to datbases dir
  throw "File source #{full_path} does not exist" unless Pathname.new(full_path).exist?
  full_path  
end

def db_source(db_source)
  current_release_path = "#{$genv.protein_database_root}/#{db_source}/current.fasta"
  throw "Database source #{current_release_path} does not exist" unless Pathname.new(current_release_path).exist?
  current_release_path  
end


def ftp_source(ftpsource)
  

  data_uri=URI.parse(ftpsource[0])
  data_file_path="#{$genv.database_downloads}/#{data_uri.host}/#{data_uri.path}"
  unpacked_data_path=data_file_path.gsub(/\.gz$/,'')

  release_notes_url=ftpsource[1]
  release_notes_exist=true
  release_notes_exist=false if (release_notes_url =~ /^\s*none\s*$/) || (release_notes_url==nil)

  release_notes_show_update_needed = true

  if release_notes_exist

    data_rn=URI.parse(release_notes_url)

    if ( data_rn != nil )
      release_notes_file_path="#{$genv.database_downloads}/#{data_rn.host}/#{data_rn.path}"

      task :check_rn do
        release_notes_show_update_needed = check_ftp_release_notes(release_notes_url) 
      end

      file release_notes_file_path => :check_rn
    end
  else
    task :check_date do

    end
  end

  
  if ( data_file_path=~/\*/) # A wildcard
    unpacked_data_path=data_file_path.gsub(/\*/,"_all_").gsub(/\.gz$/,'')
  end

  task unpacked_data_path  do #Unpacking. Includes unzipping and/or concatenating
      if ( release_notes_show_update_needed )
        download_ftp_source(ftpsource[0])
        file_pattern = Pathname.new(data_file_path).basename.to_s        

        case

      when data_file_path=~/\*/ # Multiple files to unzip/concatenate and we don't know what they are yet

        if file_pattern =~ /.gz$/
          unzipcmd="gunzip -vdf #{file_pattern}"
          p "Unzipping #{unzipcmd} ... this could take a while"
          sh %{ cd #{Pathname.new(data_file_path).dirname}; #{unzipcmd}  }             
        end

        file_pattern.gsub!(/\.gz$/,'')
        catcmd="cat #{file_pattern} > #{unpacked_data_path}"
      
        p "Concatenating files #{catcmd} ... this could take a while"
        sh %{ cd #{Pathname.new(data_file_path).dirname}; #{catcmd}  }
      
      else # Simple case. A single file 
        if file_pattern =~ /.gz$/
          p "Unzipping #{Pathname.new(data_file_path).basename} ... "
          sh %{ cd #{Pathname.new(data_file_path).dirname}; gunzip -f #{Pathname.new(data_file_path).basename}  }           
        end
      end
    end
  end

  file unpacked_data_path => release_notes_file_path if release_notes_exist

  unpacked_data_path
end

source_files=dbspec[:sources].collect do |raw_source|
  sf=""
  case 
  when raw_source.class==Array
    sf=ftp_source(raw_source)
  when (raw_source =~ /\.fasta$/ || raw_source =~ /\.txt$/ || raw_source =~ /\.dat$/ )
    sf=file_source(raw_source)
  else
    sf=db_source(raw_source)
  end
  sf  
end

########################
#  Concat Filter Copy  #
########################

raw_db_filename = "#{dbdir}/raw.#{format}"

file raw_db_filename => [source_files,dbspec_file].flatten do  

  source_filters=dbspec[:include_filters]

  if ( format == "fasta" && source_filters.length > 0 ) # We can perform concat and filter for fasta only

    archive_fasta_file(raw_db_filename) if dbspec[:archive_old]

    cleanup_file(raw_db_filename)

    output_fh=File.open(raw_db_filename, "w")

    id_regexes=dbspec[:id_regexes]
    source_i=0
    throw "The number of source files #{source_files.length} should equal the number of source filters #{source_filters.length}" unless source_filters.length == source_files.length
    throw "The number of source files #{source_files.length} should equal the number of id regexes #{id_regexes.length}" unless source_filters.length == id_regexes.length

    added_ids=Set.new

    source_files.each do |source|
      # Open source as Fasta
      #    
      Bio::FlatFile.open(Bio::FastaFormat, source) do |ff|
        p "Reading source file #{source}"

        n_match=0

        filters=source_filters[source_i] #An array of filters for this input file
        id_regex=/#{id_regexes[source_i]}/
      
        ff.each do |entry|
          filters.each do |filter|
            if ( entry.definition =~ /#{filter}/)
              n_match=n_match+1
              idmatch=id_regex.match(entry.definition)
              case 
              when idmatch==nil || idmatch[1]==nil
                p "No match to id regex #{id_regex} for #{entry.definition}. Skipping this entry"              
              else
                new_def="#{idmatch[1]}"
                if ( added_ids.include?(new_def) )
                  p "Warning: Skipping duplicate definition for #{new_def}"
                else
                  entry.definition=new_def
                  output_fh.puts(entry.to_s)
                  added_ids.add new_def
                end
                #              p entry.definition.to_s
              end
              break
            end
          end
        end
        p "Warning no match to any filter in #{filters} for source file #{source}" unless n_match > 0
      end
      source_i=source_i+1
    end
    output_fh.close
  else # Other formats just copy a file across ... must be a single source

    throw "Only a single source file is permitted for formats other than fasta" unless source_files.length == 1

    cleanup_file(raw_db_filename)

    
    sh "cp #{source_files[0]} #{raw_db_filename}" do |ok,res|
      if ! ok 
        puts "Unable to copy #{source_files[0]} to #{raw_db_filename}"
      end
    end
    
  end
end

#####################
#  Decoys           #
#####################

decoy_db_filename = "#{dbdir}/with_decoys.fasta"
file decoy_db_filename => raw_db_filename do

  archive_fasta_file(decoy_db_filename) if dbspec[:archive_old]

  cleanup_file(decoy_db_filename)

  decoys_filename = "#{dbdir}/decoys_only.fasta"
  decoy_prefix=dbspec[:decoy_prefix]

  # Count entries in the raw input file
  #  
  ff=Bio::FlatFile.open(Bio::FastaFormat, raw_db_filename)
  db_length=0
  ff.each do |entry| 
    db_length=db_length+1 
  end
  
  p "Generating decoy sequences ... this could take a while"  
  # Make decoys, concatenate and delete decoy only file
  Randomize.make_decoys raw_db_filename, db_length, decoys_filename, decoy_prefix
  cmd = "cat #{raw_db_filename} #{decoys_filename} >> #{decoy_db_filename}; rm #{decoys_filename}"
  sh %{ #{cmd} }
end

# Adjust dependencies depending on whether we're making decoys
#
case dbspec[:decoys]
when true
  throw "Decoys are only supported for fasta formatted databases" unless format=="fasta"
  file db_filename => decoy_db_filename
else
  file db_filename => raw_db_filename
end


###################
# Symlink Current #
###################


# Current database file should symlink to raw or decoy
#
file db_filename do
  if ( dbspec[:is_annotation_db])
    db_filename=raw_db_filename # For annotation databases we don't use symlinks at all
  else
    # if we are an annotation db we can't symlink so do nothing

    # source db filename is either decoy or raw
    #
    case dbspec[:decoys]
    when true
      source_db_filename = decoy_db_filename
    when false
      source_db_filename = raw_db_filename
    end

    p "Current db links to #{source_db_filename}"

    # Symlink to the source file
    #
    source_db_filename_relative = Pathname.new(source_db_filename).basename.to_s
    File.symlink(source_db_filename_relative,db_filename)
  end
end



###################
# Indexing        #
###################
if dbspec[:make_blast_index] 
#  blast_index_files=FileList.new([".phr"].collect {|ext| "#{db_filename}#{ext}"  })
  #  task :make_blast_index => blast_index_files  do
  blast_index_files=["#{db_filename}.phr"]
  blast_index_files.each do |indfile|
    file indfile => db_filename do
      cmd="cd #{dbdir}; #{$genv.makeblastdb} -in #{db_filename} -parse_seqids -dbtype prot -max_file_sz 20000000000"
      p "Creating blast index"
      sh %{ #{cmd} }
    end
  end
  
  task dbname => blast_index_files

end


if dbspec[:make_msgf_index] 
  msgf_index_files=FileList.new([".canno"].collect {|ext| "#{db_filename}#{ext}"  })
  #  task :make_blast_index => blast_index_files  do
  msgf_index_files.each do |indfile|
    file indfile => db_filename do
      cmd="cd #{dbdir}; java -Xmx3500M -cp #{$genv.msgfplusjar} edu.ucsd.msjava.msdbsearch.BuildSA -d #{db_filename} -tda 0"
      p "Creating msgf index"
      sh %{ #{cmd} }
    end
  end
  
  task dbname => msgf_index_files
end

if format=="dat" && dbspec[:is_annotation_db]
  dat_index_file= "#{dbdir}/id_AC.index"

  cleanup_file dat_index_file #Regenerate indexes every time
  
  file dat_index_file => db_filename do
    puts "Indexing annotation database"
    dbclass=Bio::SPTR
    parser = Bio::FlatFileIndex::Indexer::Parser.new(dbclass, nil, nil)
    Bio::FlatFileIndex::Indexer::makeindexFlat(dbdir, parser, {}, db_filename)
  end
  
  task dbname => dat_index_file
  
end

#################
# Root task     #
#################

task dbname => db_filename