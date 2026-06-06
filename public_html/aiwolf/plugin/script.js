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
			elm_t.innerHTML = '▲';
			actAcd = '0';
		}
		else{
			elm.style.display = "none";
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
	setAjaxEvent($(".vil_main"));
  	$('#entryname').display = 'none';
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
  var href = "./index.cgi?vid="+vid+"&date="+date+"&log=list";
  $.get(href,{},function(data){
    var list = $(data).find(".list");
    $("#list").html(list)
  });
}

function hideList(){
  $("#list").hide();
}
