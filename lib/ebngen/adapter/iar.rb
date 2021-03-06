
require_relative '_base'
require_relative '_yml_helper'
require_relative '_path_modifier'
require_relative 'iar/eww'
require_relative 'iar/ewp'
require_relative 'iar/ewd'

#replace me when yml_merger becomes gem
require 'yml_merger'
require 'nokogiri'
require 'uri'
require 'open-uri'

module IAR
class Project
	TOOLCHAIN='iar'
	include Base
	include EWP
	include EWD
	include UNI_Project

	def initialize(project_data, generator_variable, logger = nil)
		@logger = logger 
    	unless (logger)
        	@logger = Logger.new(STDOUT)
        	@logger.level = Logger::WARN
    	end
		set_hash(project_data)
		@project_name = get_project_name()
		@board = get_board()
		@paths = PathModifier.new(generator_variable["paths"])
		@iar_project_files = {".ewp" => nil, ".dni" => nil, ".ewd" => nil, ".yml" => nil}
		return nil if get_template(Project::TOOLCHAIN).nil?
		get_template(Project::TOOLCHAIN).each do |template|
			@logger.info template
			ext = File.extname(template)
			if @iar_project_files.keys.include?(ext)
				path = @paths.fullpath("default_path",template)
			  #begin
				case ext
					when ".ewp"
						doc = Nokogiri::XML(open(path))
						@iar_project_files[ext] = doc
					when ".ewd"
						doc = Nokogiri::XML(open(path))
						@iar_project_files[ext] = doc
					when ".dni"
						doc = Nokogiri::XML(open(path))
						@iar_project_files[ext] = doc
				end
			  #rescue
			  #	@logger.info "failed to open #{template}"
			  #end
			end
		end
	end

  	def generator(filter, project_data)
  		return if not is_toolchain_support(Project::TOOLCHAIN)
    	create_method( Project::TOOLCHAIN)
    	send(Project::TOOLCHAIN.to_sym, project_data)
    	save_project()
  	end

  	def source()
  		#add sources to target
  		return if @iar_project_files['.ewp'].nil?
  		remove_sources(@iar_project_files['.ewp'])
  		sources = get_src_list(Project::TOOLCHAIN)
  		o_path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
  		proj_path = File.join(@paths.rootdir_table['output_root'], o_path)
  		add_sources(@iar_project_files['.ewp'], sources, @paths, proj_path)
  	end

  	def templates()
  		#load tempaltes
  	end

  	def type()
  		#set project type
  	end

  	def document()
  		project_name = get_project_name()

  	end

	def targets()
		convert_lut = {
			'cx_flags' => 'cxx_flags',
			'cc_define' => 'cc_defines',
			'cx_define' => 'cxx_defines',
			'as_define' => 'as_defines', 
			'cp_define' => 'cp_defines',
			'ar_flags' => 'ar_flags' 
		}
		get_targets(Project::TOOLCHAIN).each do |key, value|
			next if value.nil?
			#add target for ewp
			t = new_target(key, @iar_project_files['.ewp'])
			if t.nil?
			  @logger.info "missing default debug configuration in template"
 			  return
			end
			#do the target settings
			value.each_key do |subkey|
				#for backward compatible
				temp_op = subkey.gsub('-', '_')
				if convert_lut.has_key? temp_op
					target_op = convert_lut[temp_op]
				else
					target_op = temp_op
				end
				methods = self.class.instance_methods(false)
          		if methods.include?("target_#{target_op}".to_sym)
            		send("target_#{target_op}".to_sym, t, value[subkey])
          		else
            		@logger.info "#{subkey} is not processed try to use the tool-chain specific"
          		end
			end
		end
		remove_targets(@iar_project_files['.ewp'], get_target_list(Project::TOOLCHAIN))
	end

    # tool_chain_specific attribute for each target
    # Params:
    # - target_node: the xml node of given target
    # - doc: the hash that holds the data
	def target_tool_chain_set_spec(target_node, doc)
		set_specific(target_node, doc)
	end

	def target_tool_chain_add_spec(target_node, doc)
		add_specific(target_node, doc)
	end

	def save_project()
		path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
		save(@iar_project_files['.ewp'], File.join(@paths.rootdir_table['output_root'], path, "#{@project_name}_#{@board}.ewp"))
	end

	def target_cp_defines(target_node, doc)
		value = doc.values.join(" ")
		settings = {'OGChipSelectEditMenu' => {
    				'state' => doc.keys.join("") + "\t" + value
  					}
  				}
		set_specific(target_node, settings)
		settings = {'GEndianModeBE' => {
					'state' => '1'
					}
		}
		set_specific(target_node, settings)
	end

	def target_as_predefines(target_node, doc)

	end

	def target_as_defines(target_node, doc)
		defines_array = Array.new
		doc.each do |item|
		  if item.class == Hash
		  	item.each do |key, value|
		  	  defines_array.insert(-1, "#{key}=#{value}")
		    end
		  else
	      	defines_array.insert(-1, item)
	      end
  		end
		settings = {'ADefines' => {
    				'state' => defines_array
  					}
  				}
  		add_specific(target_node, settings)
	end

	def target_as_include(target_node, doc)
		o_path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
  		proj_path = File.join(@paths.rootdir_table['output_root'], o_path)
  		settings = {'AUserIncludes' => {} }
  		inc_array = Array.new
  		doc.each do |item|
	      if item['rootdir']
	        full_path = @paths.fullpath(item['rootdir'],item['path'])
	      else
	        full_path = @paths.fullpath('default_path',item['path'])
	      end
	      inc_array.insert(-1, File.join("$PROJ_DIR$", @paths.relpath(proj_path, full_path)))
  		end
  		settings['AUserIncludes']['state'] = inc_array
  		add_specific(target_node, settings)
	end

	def target_as_flags(target_node, doc)
		flags_array = Array.new
		doc.each do |item|
		  if item.class == Hash
		  	item.each do |key, value|
		  	  flags_array.insert(-1, "#{key}=#{value}")
		    end
		  else
	      	flags_array.insert(-1, item)
	      end
  		end
		settings = {'AExtraOptionsV2' => {
    				'state' => flags_array
  					}
  				}
  		add_specific(target_node, settings)
	end

	def target_cc_predefines(target_node, doc)

	end

	def target_cc_preincludes(target_node, doc)
		o_path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
  		proj_path = File.join(@paths.rootdir_table['output_root'], o_path)
  		settings = {'PreInclude' => {} }
  		inc_array = Array.new
  		doc.each do |item|
	      if item['rootdir']
	        full_path = @paths.fullpath(item['rootdir'],item['path'])
	      else
	        full_path = @paths.fullpath('default_path',item['path'])
	      end
	      inc_array.insert(-1, File.join("$PROJ_DIR$", @paths.relpath(proj_path, full_path)))
  		end
  		settings['PreInclude']['state'] = inc_array
  		add_specific(target_node, settings)
	end

	def target_cc_defines(target_node, doc)
		defines_array = Array.new
		doc.each do |item, item_value|
		   if item_value.nil?
	         defines_array.insert(-1, "#{item}")
	       else
              defines_array.insert(-1, "#{item}=#{item_value}")
	       end
  		end
		settings = {'CCDefines' => {
    				'state' => defines_array
  					}
  				   }
  		add_specific(target_node, settings)
	end

	def target_cc_include(target_node, doc)
		o_path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
  		proj_path = File.join(@paths.rootdir_table['output_root'], o_path)
  		settings = {'CCIncludePath2' => {} }
  		inc_array = Array.new
  		doc.each do |item|
	      if item['rootdir']
	        full_path = @paths.fullpath(item['rootdir'],item['path'])
	      else
	        full_path = @paths.fullpath('default_path',item['path'])
	      end
	      inc_array.insert(-1, File.join("$PROJ_DIR$", @paths.relpath(proj_path, full_path)))
  		end
  		settings['CCIncludePath2']['state'] = inc_array
  		add_specific(target_node, settings)
	end

	def target_cc_flags(target_node, doc)
		settings_check = { 'IExtraOptionsCheck' => {
				'state' => '1'
			}
		}
		add_specific(target_node, settings_check)
		settings = {'IExtraOptions' => {
    				'state' => doc
  					}
  				   }
  		add_specific(target_node, settings)
	end

	def target_cxx_predefines(target_node, doc)
		target_cc_predefines(target_node, doc)
	end

	def target_cxx_preincludes(target_node, doc)
		target_cc_preincludes(target_node, doc)
	end

	def target_cxx_defines(target_node, doc)
		target_cc_defines(target_node, doc)
	end

	def target_cxx_include(target_node, doc)
		target_cc_include(target_node, doc)
	end

	def target_cxx_flags(target_node, doc)
		target_cc_flags(target_node, doc)
	end

	def target_ld_flags(target_node, doc)
		settings = {'IlinkConfigDefines' => {
    				'state' => doc
  					}
  				   }
  		add_specific(target_node, settings)
	end

	def target_libraries(target_node, doc)
		settings = {'IlinkAdditionalLibs' => {
    				'state' => doc
  					}
  				   }
  		add_specific(target_node, settings)
	end

	def target_linker_file(target_node, doc)
		settings_check = { 'IlinkIcfOverride' => {
				'state' => 1
			}
		}
		add_specific(target_node, settings_check)
		o_path = get_output_dir(Project::TOOLCHAIN, @paths.rootdir_table)
  		proj_path = File.join(@paths.rootdir_table['output_root'], o_path)
  		settings = {'IlinkIcfFile' => {} }
  		inc_array = Array.new
  		if doc.has_key?("rootdir")
	      full_path = @paths.fullpath(doc['rootdir'],doc['path'])
	    else
	      full_path = @paths.fullpath('default_path',doc['path'])
	    end
	    inc_array.insert(-1, File.join("$PROJ_DIR$", @paths.relpath(proj_path, full_path)))
  		settings['IlinkIcfFile']['state'] = inc_array.join(" ")
  		add_specific(target_node, settings)
	end

	def target_outdir(target_node, doc)
=begin
		<option>
          <name>IlinkOutputFile</name>
          <state>K70_pit_drivers_test.out</state>
        </option>
=end
		settings = { 'IlinkOutputFile' => {
				'state' => "#{get_project_name()}.out"
			}
		}
		set_specific(target_node, settings)
	end

end

class Project_set
	include EWW
	include UNI_Project
	TOOLCHAIN='iar'

	# initialize EWW class
    # PARAMS:
    # - project_data: specific project data format for a application/library
    # - generator_variable: all dependency in hash
	def initialize(project_data, generator_variable, logger = nil)
		@logger = logger 
    	unless (logger)
        	@logger = Logger.new(STDOUT)
        	@logger.level = Logger::WARN
    	end
		set_hash(project_data)
		@project_name = get_project_name()
		@board = get_board()
		@paths = PathModifier.new(generator_variable["paths"])
		@all_projects_hash = generator_variable["all"]
		@iar_project_files = {".eww" => nil}
		return nil if get_template(Project_set::TOOLCHAIN).nil?
		get_template(Project_set::TOOLCHAIN).each do |template|
			ext = File.extname(template)
			if @iar_project_files.keys.include?(ext)
				path = @paths.fullpath("default_path",template)
				doc = Nokogiri::XML(open(path))
				case ext
					when ".eww"
						@iar_project_files[ext] = doc
					else
						@logger.info "#{ext} not processed"
				end
			end
		end
		#clean the wrkspace in template
	 	@iar_project_files[".eww"].css("workspace/project").each do |node|
        	node.remove
    	end
	 	@iar_project_files[".eww"].css("workspace/batchBuild/batchDefinition").each do |node|
        	node.remove
    	end  	
	end

	def generator()
		return if not is_toolchain_support(Project::TOOLCHAIN)
		add_project_to_set()
		save_set()
	end


	def add_project_to_set()
		return if @iar_project_files.nil?
		return if @iar_project_files['.eww'].nil?
		ext = ".eww"

		#batch build mode is add
		get_target_list(Project_set::TOOLCHAIN).each do |target|	
			add_batch_project_target(@iar_project_files[ext], "all", @project_name, target)
			add_batch_project_target(@iar_project_files[ext], target, @project_name, target)
			next if get_libraries(Project_set::TOOLCHAIN).nil?
			get_libraries(Project_set::TOOLCHAIN).each do |lib|
				add_batch_project_target(@iar_project_files[ext], "all", lib, target)
				add_batch_project_target(@iar_project_files[ext], target, lib, target)				
			end
		end
		#add projects
		file = "#{@project_name}_#{@board}.ewp"
		path = File.join('$WS_DIR$',file)
		add_project(@iar_project_files[ext], path)
		#add library projects here
		#get from dependency['libraries'][library_name]
		ustruct = @all_projects_hash
		return if get_libraries(Project_set::TOOLCHAIN).nil?
		get_libraries(Project_set::TOOLCHAIN).each do |lib|
			if ustruct[lib].nil?
				@logger.info "#{lib} information is missing in all hash"
				next
			end
			libname = "#{@project_name}.ewp"
            root = @paths.rootdir_table[@ustruct[library][tool_key]['outdir']['root-dir']]
            lib_path = File.join(root, @ustruct[library][tool_key]['outdir']['path'], libname)
            if @ustruct[ project_name ][ tool_key ].has_key?('outdir')
                ewwpath = File.join(@output_rootdir, @ustruct[ project_name ][ tool_key ][ 'outdir' ] )
            else
                ewwpath = @output_rootdir
            end
            path = Pathname.new(lib_path).relative_path_from(Pathname.new(ewwpath))
			#more to come
		end

	end

	def save_set()
		path = get_output_dir(Project_set::TOOLCHAIN, @paths.rootdir_table)
		@logger.info  @paths.rootdir_table['output_root']
		@logger.info path
		@logger.info "#{@project_name}_#{@board}.eww"
		if path.class == Hash 
			save(@iar_project_files['.eww'], File.join(@paths.rootdir_table[path['rootdir']], path['path'], "#{@project_name}_#{@board}.eww"))
		else
		  save(@iar_project_files['.eww'], File.join(@paths.rootdir_table['output_root'], path, "#{@project_name}_#{@board}.eww"))
		end
	end

end

end # end Module IAR