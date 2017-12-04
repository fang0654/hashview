# encoding: utf-8
get '/customers/list' do
  @customers = Customers.order(Sequel.asc(:name)).all
  @total_jobs = []
  @total_hashfiles = []

  @customers.each do |customer|
    @total_jobs[customer.id] = Jobs.count(customer_id: customer.id)
    @total_hashfiles[customer.id] = Hashfiles.count(customer_id: customer.id)
  end

  haml :customer_list
end

get '/customers/create' do
  haml :customer_edit
end

post '/customers/create' do
  varWash(params)

  if !params[:name] || params[:name].nil?
    flash[:error] = 'Customer must have a name.'
    redirect to('/customers/create')
  end

  pre_existing_customer = Customers.where(name: params[:name]).all
  if !pre_existing_customer.empty? || pre_existing_customer.nil?
    flash[:error] = 'Customer ' + params[:name] + ' already exists.'
    redirect to('/customers/create')
  end

  customer = Customers.new
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/edit/:id' do
  varWash(params)
  @customer = Customers.first(id: params[:id])
  
  haml :customer_edit
end

post '/customers/edit/:id' do
  varWash(params)
  if !params[:name] || params[:name].nil?
    flash[:error] = 'Customer must have a name.'
    redirect to('/customers/create')
  end

  customer = Customers.first(id: params[:id])
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/delete/:id' do
  varWash(params)

  @customer = Customers.first(id: params[:id])
  @customer.destroy unless @customer.nil?

  @jobs = Jobs.where(customer_id: params[:id]).all
  unless @jobs.nil?
    @jobs.each do |job|
      @jobtasks = Jobtasks.where(job_id: job.id).all
      @jobtasks.destroy unless @jobtasks.nil?
    end
    @jobs.destroy unless @jobs.nil?
  end

  # @hashfilehashes = Hashfilehashes.all(hashfile_id:
  # Need to select/identify what hashfiles are associated with this customer then remove them from hashfilehashes

  @hashfiles = Hashfiles.where(customer_id: params[:id]).all
  @hashfiles.destroy unless @hashfiles.nil?

  redirect to('/customers/list')
end

post '/customers/upload/hashfile' do
  # varWash(params)

  if params[:hashfile_name].nil? || params[:hashfile_name].empty?
    flash[:error] = 'You must specificy a name for this hash file.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  if params[:file].nil? || params[:file].empty?
    flash[:error] = 'You must specify a hashfile.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  @job = Jobs.first(id: params[:job_id])
  return 'No such job exists' unless @job

  # temporarily save file for testing
  hash = rand(36**8).to_s(36)
  hashfile = "control/hashes/hashfile_upload_job_id-#{@job.id}-#{hash}.txt"

  # Parse uploaded file into an array
  hash_array = []
  whole_file_as_string_object = params[:file][:tempfile].read
  File.open(hashfile, 'w') { |f| f.write(whole_file_as_string_object) }
  whole_file_as_string_object.each_line do |line|
    hash_array << line
  end

  # save location of tmp hash file
  hashfile = Hashfiles.new
  hashfile.name = params[:hashfile_name]
  hashfile.customer_id = params[:customer_id]
  hashfile.hash_str = hash
  hashfile.save

  @job.save # <---- edit bug here

  redirect to("/customers/upload/verify_filetype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{hashfile.id}")
end

post '/customers/upload/hashes' do
  # varWash(params)

  if params[:hashfile_name].nil? || params[:hashfile_name].empty?
    flash[:error] = 'You must specificy a name for this hash file.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  if params[:hashes].nil? || params[:hashes].empty?
    flash[:error] = 'You must supply at least one hash.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  @job = Jobs.first(id: params[:job_id])
  return 'No such job exists' unless @job

  # temporarily save file for testing
  hash = rand(36**8).to_s(36)
  hashfile = "control/hashes/hashfile_upload_job_id-#{@job.id}-#{hash}.txt"

  # Parse uploaded file into an array
  hash_array = params[:hashes].to_s.gsub(/\x0d\x0a/, "\x0a") # in theory we shouldnt run into any false positives?
  File.open(hashfile, 'w') { |f| f.puts(hash_array) } 

  # save location of tmp hash file
  hashfile = Hashfiles.new
  hashfile.name = params[:hashfile_name]
  hashfile.customer_id = params[:customer_id]
  hashfile.hash_str = hash
  hashfile.save

  @job.save # Edit bug here <----

  redirect to("/customers/upload/verify_filetype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{hashfile.id}")
end

get '/customers/upload/verify_filetype' do
  varWash(params)

  @filetypes = ['pwdump', 'shadow', 'dsusers', 'smart_hashdump', '$hash', '$user:$hash', '$hash:$salt', '$user:$hash:$salt', '$user::$domain:$hash:$hash:$hash (NetNTLMv1)', '$user::$domain:$challenge:$hash:$hash (NetNTLMv2)']
  @job = Jobs.first(id: params[:job_id])
  haml :verify_filetypes
end

post '/customers/upload/verify_filetype' do
  varWash(params)

  if !params[:filetype] || params[:filetype].nil? || params[:filetype] == '- SELECT -'
    flash[:error] = 'You must specify a valid hashfile type.'
    redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  end

  params[:filetype] = 'hash_only' if params[:filetype] == '$hash'
  params[:filetype] = 'user_hash' if params[:filetype] == '$user:$hash'
  params[:filetype] = 'hash_salt' if params[:filetype] == '$hash:$salt'
  params[:filetype] = 'user_hash_salt' if params[:filetype] == '$user:$hash:$salt'
  params[:filetype] = 'NetNTLMv1' if params[:filetype] == '$user::$domain:$hash:$hash:$hash NetNTLMv1'
  params[:filetype] = 'NetNTLMv2' if params[:filetype] == '$user::$domain:$challenge:$hash:$hash NetNTLMv2'

  redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
end

get '/customers/upload/verify_hashtype' do
  varWash(params)

  hashfile = Hashfiles.first(id: params[:hashid])

  @hashtypes = detectHashType("control/hashes/hashfile_upload_job_id-#{params[:job_id]}-#{hashfile.hash_str}.txt", params[:filetype])
  @job = Jobs.first(id: params[:job_id])
  haml :verify_hashtypes
end

post '/customers/upload/verify_hashtype' do
  varWash(params)

  filetype = params[:filetype]
  hashfile = Hashfiles.first(id: params[:hashid])

  params[:hashtype] == '99999' ? hashtype = params[:manualHash] : hashtype = params[:hashtype]

  hash_file = "control/hashes/hashfile_upload_job_id-#{params[:job_id]}-#{hashfile.hash_str}.txt"

  hash_array = []
  chunk_max = 1000000 # 1M
  chunk_cnt = 0
  time = 0
  File.open(hash_file, 'r').each do |line|
    if chunk_cnt < chunk_max
      hash_array << line
      chunk_cnt += 1
      # p 'CHUNK_CNT: ' + chunk_cnt.to_s
    else
      # p 'HASH_ARRAY' + hash_array.to_s
      hash_array << line # I think this is needed for off by one imports
      #time += Benchmark.measure {
      unless importHash(hash_array, hashfile.id, filetype, hashtype)
        flash[:error] = 'Error importing hashes'
        redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
      end
      #}
      hash_array = []
      chunk_cnt = 0
    end
  end
  # Sloppy code to put this twice
  # time += Benchmark.measure {
  if hash_array.size > 0
    unless importHash(hash_array, hashfile.id, filetype, hashtype)
      flash[:error] = 'Error importing hashes'
      redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
    end
  end
  # }

  @job = Jobs.first(id: params[:job_id])
  @job.hashfile_id = hashfile.id
  @job.save

  #time += Benchmark.measure {
  #  unless importHash(hash_array, hashfile.id, filetype, hashtype)
  #    flash[:error] = 'Error importing hashes'
  #    redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  #  end
  #}

  total_cnt = HVDB.fetch('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[:count]
  total_cnt =   total_cnt[:count]

  unless total_cnt.nil?
    #flash[:success] = 'Successfully uploaded ' + total_cnt + ' hashes.'
    flash[:success] = 'Successfully uploaded ' + total_cnt + ' hashes taking a total of ' + time.real.to_s + ' seconds.'
  end

  # Delete file, no longer needed
  File.delete(hash_file)

  url = '/jobs/local_check'

  url += "?job_id=#{params[:job_id]}"
  url += '&edit=1' if params[:edit]
  redirect to(url)
end
