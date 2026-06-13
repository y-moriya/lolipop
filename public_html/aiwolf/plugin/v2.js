var ajaxitems;

function vil_link(obj) {
  var urlValue = obj.value;
  var thisUrl = document.URL.replace(/vid\=.+/,'vid=');
  window.location.href = thisUrl+urlValue+"#form";
}

function imgChange(set) {
	var index = document.entryForm.pid.selectedIndex;
	var str = document.entryForm.pid.options[index].value;
	if (str.length < 2) {
		str = "0" + str;
	}
	document.entryForm.charaImg.src = "img/" + set + str + ".png";
}

function dateChange(vid,obj) {
  var urlValue = obj.value;
  var thisUrl = document.URL.replace(/vid\=.+/,'vid=');
  window.location.href = thisUrl+vid+"&date="+urlValue;
}

function dummyChange(sets) {
	var index = document.mkvilForm.char.selectedIndex;
	document.mkvilForm.dummyImg.src = "img/" + sets[index] + "00.png";
}

function compChange() {
	var forms = document.getElementsByTagName("form");
	if(!forms[0]) return;
	var index = document.forms[0].composition.selectedIndex;
	var str = "comp" + document.forms[0].composition.options[index].value;
	var elements = document.getElementsByTagName("div");
	for (i = 0; i < elements.length; i++){
		if(/comp\d+/, elements[i].id){
			if(elements[i].id != str){
				elements[i].style.display = "none";
			}
			else{
				elements[i].style.display = "block";
			}
		}
	}
}

function focusMessage() {
	var forms = document.getElementsByName("focus_form");
	if (forms[0]){
		if (document.URL.match(/#form/)) {
			location.href = "#form";
			forms[0].message.focus();
		}
	}
}

function syncActAcd() {
	if (actAcd == "0"){
		actToggle('box_act', 'act_tog');
	}
}

function getCookie(name) {
	var start = document.cookie.indexOf(name + "=");
	var len = start + name.length + 1;
	if (start == -1) return null;
	var end = document.cookie.indexOf( ';', len );
	if (end == -1) end = document.cookie.length;
	return document.cookie.substring(len, end);
}

function writeCookie() {
	var etime = new Date();
	etime.setTime(etime.getTime()+(30*24*60*60*5000));
	document.cookie = "actacd=" + actAcd + ";" + "expires=" + etime.toGMTString();
}

function actToggle(obj_id, obj_t_id) {
	var elm = document.getElementById(obj_id);
	var elm_t = document.getElementById(obj_t_id);
	if(elm_t){
		if(elm.style.display == 'none'){
			elm.style.display = "block";
			$(elm).addClass('v2-action-box-visible');
			elm_t.innerHTML = '▲';
			actAcd = '0';
		}
		else{
			elm.style.display = "none";
			$(elm).removeClass('v2-action-box-visible');
			elm_t.innerHTML = '▼';
			actAcd = '1';
		}
		writeCookie();
	}
}

function spToggle(obj_id, obj_t_id) {
	var elm = document.getElementById(obj_id);
	var elm_t = document.getElementById(obj_t_id);
	if(elm_t){
		if(elm.style.display == 'none'){
			elm.style.display = "block";
		}
		else{
			elm.style.display = "none";
		}
	}
}

function init() {
	actAcd = '1';
	actAcd = getCookie('actacd');
	syncActAcd();
	focusMessage();
	ajaxitems = [];

	var isV2 = window.location.pathname.indexOf('v2.cgi') !== -1;
	if (isV2) {
		initV2AnchorHover();
		initResponsivePlayers();
		initModernChat();
	} else {
		setAjaxEvent($(".vil_main"));
	}

  	$('#entryname').display = 'none';
	if (typeof lastEventId !== 'undefined') {
		pollEvents();
	}
}

function hideSelectBoxes(popL, popR, popT, popD){
	var element;
	var selectL;
	var selectR;
	var selectT;
	var selectD;
	selects = document.getElementsByTagName("select");
	for (i = 0; i != selects.length; i++) {
		element = selects[i];
		selectL = 0;
		selectT = 0;
		do {
			selectL += element.offsetLeft || 0;
			selectT += element.offsetTop || 0;
			element = element.offsetParent;
		} while (element);
		selectR = selectL + selects[i].offsetWidth;
		selectD = selectT + selects[i].offsetHeight;
		if (selectL <= popR && selectR >= popL && selectT <= popD && selectD >= popT){
			selects[i].style.visibility = "hidden";
		}
	}
}

function showSelectBoxes(){
	selects = document.getElementsByTagName("select");
	for (i = 0; i != selects.length; i++) {
		selects[i].style.visibility = "visible";
	}
}

function popup(pid, name, time, type, msg, e){
	if (!document.getElementById('popup')){
		var div = document.createElement('div');
		var offsetX = 20;
		var offsetY = 20;
		var d = document.documentElement;
		var scrollX = (window.scrollX || d.scrollLeft || document.body.scrollLeft);
		var scrollY = (window.scrollY || d.scrollTop || document.body.scrollTop);
		var windowW = (window.innerWidth || d.offsetWidth);
		var windowH = (window.innerHeight || d.offsetHeight);
		var mouseX = (navigator.userAgent.match('AppleWebKit') && (navigator.appVersion.charAt(0) < 3)) ? e.clientX - scrollX : e.clientX;
		var mouseY = (navigator.userAgent.match('AppleWebKit') && (navigator.appVersion.charAt(0) < 3)) ? e.clientY - scrollY : e.clientY;

		div.id = 'popup';
		var str = "<span class=\"char_name\">" + name + "</span>" + "<span class=\"time\"> " + time + "</span>";
		div.innerHTML = "<table class=\"message\"><tr><td width=\"50\" rowspan=\"2\"><img src=\"" + pid + ".png\"></td><td colspan=\"2\">" + str + "</td></tr><tr><td><div class=\"mes_" + type + "\"><\/div></td><td width=\"464\"><div class=\"mes_" + type + "_body0\"><div class=\"mes_" + type + "_body1\">" + msg.replace(/&apos;/g, "'") + "</div></div></td></tr></table>";

		var s = div.style;
		s.position = 'absolute';
		s.padding = '6px 6px 0px 6px';
		s.border = '2px solid #666';
		s.color = 'black';
		s.backgroundColor = '#000';
		document.body.appendChild(div);
		var popW = div.offsetWidth;
		var popH = div.offsetHeight;
		var overX = mouseX + offsetX + popW + 30 - windowW;
		var popX = (overX < 0) ? mouseX + offsetX : (mouseX + offsetX - overX > 0) ? mouseX + offsetX - overX : 0;
		var popY = (mouseY + offsetY + popH + 8 > windowH && mouseY - offsetY - popH > 0) ? mouseY - offsetY - popH : mouseY + offsetY;
		var popL = popX + scrollX;
		var popR = popL + popW;
		var popT = popY + scrollY;
		var popD = popT + popH;
		div.style.left = popL + 'px';
		div.style.top = popT + 'px';
		hideSelectBoxes(popL, popR, popT, popD);
	}
}

function popdown(){
	if (document.getElementById('popup')){
		document.body.removeChild(document.getElementById('popup'));
		showSelectBoxes();
	}
}

function showPlagin(idno){
pc = ('PlagClose' + (idno));
pc2 = ('PlagClosex' + (idno));
po = ('PlagOpen' + (idno));
if( document.getElementById(pc).style.display == "none" ) {
document.getElementById(pc).style.display = "block";
document.getElementById(pc2).style.display = "block";
document.getElementById(po).style.display = "none";
}
else {
document.getElementById(pc).style.display = "none";
document.getElementById(pc2).style.display = "none";
document.getElementById(po).style.display = "block";
}
}

function entryName(obj){
  if (obj.checked) {
    document.getElementById('entryname').style.display = 'block';
  } else {
    document.getElementById('entryname').style.display = 'none';
    document.getElementById('cname').value = '';
  }
}

function setAjaxEvent(target){
	target.find(".say").toggle(
	function(mouse){
		var ank  = $(this);
		var base = ank.parents(".message");
		var actbase = ank.parents(".announce");
		//var div = $("#popup");
		//alert(div.css('left'));
		var text = ank.text();
		if( 0 == text.indexOf(">>") ){
			var href = this.href.replace("all","anc").replace("#","&num=");
			$.get(href,{},function(data){
				var mes = $(data).find(".message");
				var time = $(mes).find(".time");
				var close = $("<span class=\"close\">×</span>");
				mes.addClass("ajax").css('display','none');
				setAjaxEvent(mes);
				time.after(close);
				base.after(mes);
				actbase.after(mes);
				ajaxitems.push(mes);
				closeWindow();
				var topm    = mouse.pageY +  16;
				var leftm   = mouse.pageX - 50; // 決めうち、本当はよくない。
				var leftend = $("body").width() - mes.width() - 8;
				if( leftend < leftm )
					leftm   = leftend;
				mes.css({top:topm,left:leftm,zIndex:'auto'});
				mes.css('background-color', '#000');
				mes.fadeIn();
				$(".ajax").easydrag();
			});
		}else{
			window.open(this.href, '_blank');
			return false;
		}
		return false;
	},function(mouse){
		var ank  = $(this);
		var base = ank.parents(".message");
		base.nextAll(".ajax").fadeOut("nomal", function(){
			base.nextAll(".ajax").remove();
		});
		var ank  = $(this);
		var actbase = ank.parents(".announce");
		actbase.nextAll(".ajax").fadeOut("nomal", function(){
			actbase.nextAll(".ajax").remove();
		});
		return false;
	});
}

function closeWindow() {
	$(".close").toggle(
	function(){
		var ank  = $(this);
		var base = ank.parents(".message");
		base.remove();
		return false;
	},function(){
		var ank  = $(this);
		var base = ank.parents(".message");
		base.remove();
		return false;
	});
}

function setList(vid,date){
  $("#list").show();
  var currentScript = window.location.pathname.split('/').pop() || 'index.cgi';
  if (!currentScript.match(/^(index|v2)\.cgi$/)) {
    currentScript = 'index.cgi';
  }
  var href = "./" + currentScript + "?vid="+vid+"&date="+date+"&log=list";
  $.get(href,{},function(data){
    var list = $(data).find(".list");
    $("#list").html(list)
  });
}

function hideList(){
  $("#list").hide();
}

var pollStopped = false;

function showReloadPrompt(content) {
  pollStopped = true;
  if ($('.reload-prompt').length > 0) return;
  
  var html = '<div class="announce reload-prompt" style="border: 2px solid #ef4444; background: rgba(239, 68, 68, 0.15); color: #fca5a5; text-align: center; padding: 16px; margin: 20px 0; border-radius: 12px; font-weight: bold; cursor: pointer; box-shadow: 0 0 15px rgba(239, 68, 68, 0.3);" onclick="window.location.reload()">' +
             '  <div style="font-size: 110%; margin-bottom: 8px;">🔄 【進行状況更新】' + escapeHtml(content) + '</div>' +
             '  <div>ゲームの状態が変化しました。ここをクリックしてページをリロードしてください。</div>' +
             '</div>';
             
  var $container = $(".chat-container");
  if ($container.length > 0) {
    if ($container.attr("data-up2down") === "1") {
      $container.prepend(html);
    } else {
      $container.append(html);
    }
  } else {
    $(".action_box").first().before(html);
  }
  
  $('html, body').animate({ scrollTop: $(document).height() }, 'slow');
}

function pollEvents() {
  if (pollStopped) return;
  if (typeof lastEventId === 'undefined' || currentVid <= 0) return;

  var url = "./api.cgi?cmd=events&vid=" + currentVid + "&since=" + lastEventId;
  $.ajax({
    url: url,
    method: "GET",
    dataType: "json",
    timeout: 20000,
    success: function(events) {
      if (pollStopped) return;
      if (events && events.length > 0) {
        var added = false;
        events.forEach(function(e) {
          if (e.id > lastEventId) {
            lastEventId = e.id;
            if (appendEventToUI(e)) {
              added = true;
            }
          }
        });
        if (added) {
          $('html, body').animate({ scrollTop: $(document).height() }, 'slow');
        }
      }
      if (!pollStopped) {
        setTimeout(pollEvents, 100);
      }
    },
    error: function(xhr, status, error) {
      if (!pollStopped) {
        setTimeout(pollEvents, 2000);
      }
    }
  });
}

function appendEventToUI(e) {
  if (e.type === 'state_change' || (e.type === 'system' && (
    e.content.indexOf('の勝利です') !== -1 ||
    e.content.indexOf('ゲームが決着しました') !== -1 ||
    e.content.indexOf('ゲーム終了') !== -1 ||
    e.content.indexOf('夜になりました') !== -1 ||
    e.content.indexOf('朝になりました') !== -1 ||
    e.content.indexOf('犠牲者') !== -1 ||
    e.content.indexOf('おぞましいダニエル') !== -1
  ))) {
    showReloadPrompt(e.content);
    return true;
  }

  if (e.type === 'message') {
    if ($('table[data-event-id="' + e.id + '"]').length > 0) return false;
    
    var imgName;
    if (e.type_code === 'whisperhowl') {
      // 狼の遠吠えは常に howl アイコンを使用（キャラアイコンを使わない）
      imgName = 'howl';
    } else {
      imgName = e.avatar;
      if (!imgName) {
        imgName = (e.speaker_id !== null && typeof avatarMapping[e.speaker_id] !== 'undefined') ? avatarMapping[e.speaker_id] : avatarMapping[-1];
      } else if (e.speaker_id !== null) {
        avatarMapping[e.speaker_id] = imgName;
      }
    }
    var imgSrc = "img/" + imgName + ".png";
    var mark = "";
    if (e.type_code === 'whisper') mark = "*";
    else if (e.type_code === 'think') mark = "-";
    else if (e.type_code === 'groan') mark = "+";
    
    var type = e.type_code;
    if (type === 'whisperhowl') type = 'whisper';
    
    var speakerLink = "";
    if (e.speaker_id !== null) {
      speakerLink = '<a href="?vid=' + currentVid + '&id=' + e.speaker_id + '&date=' + e.day + '" target="_blank">' + e.speaker + '</a>';
    } else {
      speakerLink = '<a href="?cmd=user&uid=' + encodeURIComponent(e.speaker) + '" target="_blank">' + e.speaker + '</a>';
    }
    
    var safeContent = escapeHtml(e.content).replace(/\\n/g, '<br>');
    var eventDay = e.day || 1;
    safeContent = safeContent.replace(/&gt;&gt;(\d+):([*+-]?)(\d+)|&gt;&gt;([*+-]?)(\d+)/g, function(match, d1, mark1, n1, mark2, n2) {
      var targetDay = d1 ? d1 : eventDay;
      var mark = d1 ? mark1 : mark2;
      var num = d1 ? n1 : n2;
      var t = 'say';
      if (mark === '*') t = 'whisper';
      else if (mark === '-') t = 'think';
      else if (mark === '+') t = 'groan';
      return '<a class="say" href="?vid=' + currentVid + '&date=' + targetDay + '&log=all#' + t + num + '">' + match + '</a>';
    });
    
    var html = '<table class="message" data-event-id="' + e.id + '">' +
               '<tr>' +
               '  <td width="100" rowspan="2"><img src="' + imgSrc + '" style="width:70px; height:70px; object-fit:cover; border-radius:12px; border:1px solid rgba(255,255,255,0.05); box-shadow:0 4px 6px rgba(0,0,0,0.2);"></td>' +
               '  <td colspan="2">' + speakerLink + ' <span class="time">' + e.time + '</span></td>' +
               '</tr>' +
               '<tr>' +
               '  <td valign="top"><div class="mes_' + type + '"></div></td>' +
               '  <td width="584" valign="top">' +
               '    <div class="mes_' + type + '_body0">' +
               '      <div class="mes_' + type + '_body1">' + safeContent + '</div>' +
               '    </div>' +
               '  </td>' +
               '</tr>' +
               '</table>';
               
    var $container = $(".chat-container");
    if ($container.length > 0) {
      if ($container.attr("data-up2down") === "1") {
        $container.prepend(html);
      } else {
        $container.append(html);
      }
    } else {
      $(".action_box").first().before(html);
    }
    return true;
  } else if (e.type === 'system') {
    if ($('div[data-event-id="' + e.id + '"]').length > 0) return false;
    
    var announceClass = "announce";
    if (e.type_code === 'whisperhowl') announceClass = "announce";
    
    var safeContent = escapeHtml(e.content).replace(/\\n/g, '<br>');
    var html = '<div class="' + announceClass + '" data-event-id="' + e.id + '">' + safeContent + '</div>';
    
    var $container = $(".chat-container");
    if ($container.length > 0) {
      if ($container.attr("data-up2down") === "1") {
        $container.prepend(html);
      } else {
        $container.append(html);
      }
    } else {
      $(".action_box").first().before(html);
    }
    return true;
  }
  return false;
}

function escapeHtml(string) {
  if (typeof string !== 'string') {
    return '';
  }
  return string.replace(/[&<>"']/g, function(match) {
    return {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    }[match];
  });
}

var anchorCache = {};
function initV2AnchorHover() {
  $(document).on('mouseenter', 'a.say', function(e) {
    var ank = $(this);
    ank.data('hovering', true);
    var text = ank.text();
    if (text.indexOf('>>') !== 0) return;

    var href = ank.attr('href');
    if (!href) return;

    var $popup = $('#anchor-popup');
    if ($popup.length === 0) {
      $popup = $('<div id="anchor-popup"></div>').appendTo('body');
    }

    var loadAndShow = function(htmlContent) {
      $popup.html(htmlContent);
      $popup.show();

      var ankOffset = ank.offset();
      var ankHeight = ank.outerHeight();
      var popupW = $popup.outerWidth();
      var popupH = $popup.outerHeight();

      var top = ankOffset.top - popupH - 10;
      var left = ankOffset.left - 20;

      if (top < $(window).scrollTop()) {
        top = ankOffset.top + ankHeight + 10;
      }
      if (left + popupW > $(window).width()) {
        left = $(window).width() - popupW - 10;
      }
      if (left < 0) left = 10;

      $popup.css({
        top: top + 'px',
        left: left + 'px'
      });
    };

    if (anchorCache[href]) {
      loadAndShow(anchorCache[href]);
    } else {
      var fetchUrl = href.replace("all", "anc").replace("#", "&num=");
      $.get(fetchUrl, {}, function(data) {
        var $mes = $(data).find(".message");
        if ($mes.length > 0) {
          var html = $mes.prop('outerHTML');
          anchorCache[href] = html;
          if (ank.data('hovering')) {
            loadAndShow(html);
          }
        }
      });
    }
  }).on('mouseleave', 'a.say', function() {
    var ank = $(this);
    ank.data('hovering', false);
    var $popup = $('#anchor-popup');
    if ($popup.length > 0) {
      $popup.hide();
    }
  });
}

function initResponsivePlayers() {
  var $originalList = $('table.list');
  if ($originalList.length === 0) return;

  var $btn = $('<button id="show-players-btn" type="button">👤 参加者一覧</button>');
  $('body').append($btn);

  var $modal = $(
    '<div id="players-modal">' +
    '  <div class="modal-overlay"></div>' +
    '  <div class="modal-content">' +
    '    <button type="button" class="modal-close-btn">&times;</button>' +
    '    <div class="modal-body"></div>' +
    '  </div>' +
    '</div>'
  );
  $('body').append($modal);

  if (typeof IntersectionObserver !== 'undefined') {
    var observer = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        var listTop = $originalList.offset().top;
        var scrollTop = $(window).scrollTop();
        if (!entry.isIntersecting && scrollTop > listTop) {
          $btn.addClass('visible');
        } else {
          $btn.removeClass('visible');
        }
      });
    }, { threshold: 0 });
    observer.observe($originalList[0]);
  } else {
    $(window).on('scroll', function() {
      var listTop = $originalList.offset().top;
      var listHeight = $originalList.outerHeight();
      var scrollTop = $(window).scrollTop();
      if (scrollTop > listTop + listHeight) {
        $btn.addClass('visible');
      } else {
        $btn.removeClass('visible');
      }
    });
  }

  $btn.on('click', function() {
    var $modalBody = $modal.find('.modal-body');
    $modalBody.empty();
    var $clonedList = $originalList.clone();
    $modalBody.append($clonedList);
    $modal.addClass('active');
    $('body').css('overflow', 'hidden');
  });

  var closeModal = function() {
    $modal.removeClass('active');
    $('body').css('overflow', '');
  };

  $modal.find('.modal-close-btn').on('click', closeModal);
  $modal.find('.modal-overlay').on('click', closeModal);
}

function initModernChat() {
  $(document).on('click', '.modern-chat-box .chat-tab', function() {
    var $tab = $(this);
    var mode = $tab.data('mode');
    var $box = $tab.closest('.modern-chat-box');
    
    // Set active tab styling
    $box.find('.chat-tab').removeClass('active');
    $tab.addClass('active');
    
    // Set data-mode attribute on form for CSS styling
    $box.attr('data-mode', mode);
    
    // Update hidden parameters
    var $thinkInput = $box.find('#chat-think-input');
    var $whisperInput = $box.find('#chat-whisper-input');
    var $groanInput = $box.find('#chat-groan-input');
    
    // Reset all mode values
    $thinkInput.val('');
    $whisperInput.val('');
    $groanInput.val('');
    
    // Set active mode parameter
    if (mode === 'think') {
      $thinkInput.val('on');
    } else if (mode === 'whisper') {
      $whisperInput.val('on');
    } else if (mode === 'groan') {
      $groanInput.val('on');
    }
  });

  // Remove background/border from parent td when it contains #box_act
  $('.action_balloon td.action_body:has(#box_act)').css({
    'background': 'transparent',
    'border': 'none',
    'padding': '0',
    'box-shadow': 'none'
  });

  // If syncActAcd initialized it as visible, make sure the class is added
  var $boxAct = $('#box_act');
  if ($boxAct.length && $boxAct.css('display') !== 'none') {
    $boxAct.addClass('v2-action-box-visible');
  }

  // Hide empty rows inside action balloon
  $('.action_balloon td.action_body').each(function() {
    var $this = $(this);
    if ($this.find('.modern-chat-box').length > 0) {
      $this.css('padding', '0');
    } else if ($this.find('#box_act').length === 0) {
      var text = $this.text().replace(/\s+/g, '').trim();
      if (text === '' && $this.children().length === 0) {
        $this.closest('tr').hide();
      }
    }
  });
}
