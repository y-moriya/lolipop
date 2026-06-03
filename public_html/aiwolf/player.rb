# -*- coding: euc-jp -*-
class Player
	attr_reader :pid, :userid, :num_id, :name, :num_char
	attr_accessor :dead
	attr_accessor :vote, :target, :target2, :sid, :say_cnt, :say_remain, :action_remain, :fortune_t, :fortune_id_t, :guard_t, :commit, :lovers
	attr_accessor :win
	attr_accessor :tenko

	def initialize(pid, userid, num_id, skill, name, num_char)
		@pid = pid
		@userid = userid
		@num_id = num_id
		@sid = skill
		@num_char = num_char

		@dead = 0
		@say_cnt = 0

		@vote = -1
		@target = -1
		@target2 = -1
		@fortune_t = Hash.new
		@fortune_id_t = Hash.new
		@guard_t = Hash.new
		@lovers = Array.new
		@commit = -1
		@name = (num_char < 2) ? name : "#{name}#{num_char.to_s}"
		@win = -1
		@tenko = -1
	end

	def can_whisper
		@sid == 1 || @sid == 8
	end
end

