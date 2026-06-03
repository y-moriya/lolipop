# -*- coding: utf-8 -*-
class ErrorMsg < RuntimeError
  def initialize(msg)
    @msg = msg
  end

  def to_s
    @msg
  end
end
