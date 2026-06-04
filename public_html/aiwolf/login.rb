# -*- coding: utf-8 -*-
class Login
	attr_reader :userid, :pass, :cookie, :login
 
	def set_cookie(cgi)
		if (!@userid)
			return
		end
		@cookie = CGI::Cookie.new({"name" => 'login', "value" => "#{@userid},#{@pass}"})
		@cookie.expires = Time.now + 60*60*24*30
		#@cookie.expires = Time.now + 15
		#@cookie.path = MY_PATH
	end

	def initialize(cgi)
		userdb = PStore.new('db/user.db')
		recorddb = PStore.new('db/record.db')
		cookie = cgi.cookies['login']
		@login = false

		debug_info = []
		debug_info << "Cookie: #{cookie ? cookie.inspect : 'nil'}"

		if (cookie && cookie.size == 1)
			val_str = CGI.unescape(cookie[0].to_s)
			debug_info << "Cookie unescaped: #{val_str.inspect}"
			vals = val_str.split(/,/)
      		@userid = vals[0]
			@pass = vals[1]
			debug_info << "Parsed user: #{@userid.inspect}, pass: #{@pass.inspect}"

			userdb.transaction do
				debug_info << "User in DB: #{userdb.root?(@userid)}"
				if (userdb.root?(@userid))
					db_pass = userdb[@userid]['pass']
					debug_info << "DB pass: #{db_pass.inspect}, input pass: #{@pass.inspect}"
					if (@pass == db_pass)
						@login = true
					end
				end
			end
		end
		debug_info << "Login status: #{@login}"

		begin
			File.open('db/login_debug.log', 'a') do |f|
				f.puts "[#{Time.now}] #{debug_info.join(' | ')}"
			end
		rescue => e
			# ignore
		end

		if(@login == true)
			set_cookie(cgi)
		end
			
		cmd = cgi['cmd']
	
		if (cmd == 'logout')
			@login = false
			@userid = ''
			@pass = ''
			set_cookie(cgi)

		elsif(cmd == 'login')
			userid = cgi['userid']
			@userid = CGI.escapeHTML(Kconv.toutf8(userid))
			@pass = Kconv.toutf8(cgi['pass'])
			if(@userid == '' || @pass == '')
				print "Status: 302 Found\n"
	        	print "Location: index.cgi\n\n"
				exit(0)
			end

			userdb.transaction do
				if (!userdb.root?(@userid))
					userdb[@userid] = Hash.new
					userdb[@userid]['userid'] = @userid
					userdb[@userid]['pass'] = @pass
				end
			end
=begin
			recorddb.transaction do
				if (!recorddb.root?(@userid))
					recorddb[@userid] = Array.new
				end
			end
=end
			set_cookie(cgi)
		end

		if (cmd == 'login' || cmd == 'logout')
			print "Status: 302 Found\n"
			print "Set-Cookie: #{@cookie}\n"
        	print "Location: index.cgi\n\n"
			exit(0)
		end
	end
end
