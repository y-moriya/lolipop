# -*- coding: euc-jp -*-
class Conf
	attr_reader :up2down, :win_id, :focus, :part

	def initialize(userid, cgi = nil)
		confdb = PStore.new('db/conf.db')
		confdb.transaction do
			if (confdb.root?(userid))
				confdb[userid]['up2down'] = 0 if (!confdb[userid].key?('up2down'))
				confdb[userid]['win_id'] = 0 if (!confdb[userid].key?('win_id'))
				confdb[userid]['focus'] = 0 if (!confdb[userid].key?('focus'))
				confdb[userid]['part'] = 0 if (!confdb[userid].key?('part'))

				@up2down = confdb[userid]['up2down']
				@win_id = confdb[userid]['win_id']
				@focus = confdb[userid]['focus']
				@part = confdb[userid]['part']
			else
				confdb[userid] = Hash.new 
				@up2down = 0
				@win_id = 0
				@focus = 0
				@part = 0
				confdb[userid]['up2down'] = @up2down
				confdb[userid]['win_id'] = @win_id
				confdb[userid]['focus'] = @focus
				confdb[userid]['part'] = @part
			end

			if (cgi)
				confdb[userid]['up2down'] = cgi['up2down'].to_i if (cgi.key?('up2down'))
				confdb[userid]['win_id'] = cgi['win_id'].to_i if (cgi.key?('win_id'))
				confdb[userid]['focus'] = cgi['focus'].to_i if (cgi.key?('focus'))
				confdb[userid]['part'] = cgi['part'].to_i if (cgi.key?('part'))
			end
		end
	end
end
