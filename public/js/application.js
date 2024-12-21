(function($) {
    $.fn.invisible = function() {
        return this.each(function() {
            $(this).css("visibility", "hidden");
        });
    };
    $.fn.visible = function() {
        return this.each(function() {
            $(this).css("visibility", "visible");
        });
    };
}(jQuery));

function checkStatus(response) {
	if (response.status >= 200 && response.status < 300) {
	    return response
	} else {
		var error = new Error(response.statusText)
		error.response = response
		throw error
	}
}

function parseJSON(response) {
  return response.json()
}

function checkResultStatus(response) {
    if (response.status != "ok") {
        var error = new Error(response.error || 'unknown')
        error.response = response;
        throw error
    }
    return response;
}

bootstrap_alert = function() {}
bootstrap_alert.error = function(message) {
            $('#alert_placeholder').html(
            '<div class="alert alert-danger alert-dismissible fade show">' +
            message +
            '<button type="button" class="close" data-dismiss="alert" aria-label="Close">' +
    		'<span aria-hidden="true">&times;</span>' +
  			'</button>' +
            '</div>'
        )
};
bootstrap_alert.success = function(message) {
            $('#alert_placeholder').html(
            '<div class="alert alert-success alert-dismissible fade show">' +
            message +
            '<button type="button" class="close" data-dismiss="alert" aria-label="Close">' +
    		'<span aria-hidden="true">&times;</span>' +
  			'</button>' +
            '</div>'
        )
};

function format_pos_x( pos ) {
  if (typeof pos !== 'number') {
    return '-';
  }
  if (!page_ctx.printer_resolution_x) {
    return '-';
  }
  return (pos / page_ctx.printer_resolution_x).toFixed(3);;
}

function format_pos_y( pos ) {
  if (typeof pos !== 'number') {
    return '-';
  }
  if (!page_ctx.printer_resolution_y) {
    return '-';
  }
  return (pos / page_ctx.printer_resolution_y).toFixed(3);
}

function update_state( data ) {
    if (state.state !== data.state) {
        console.log('change state ' + state.state + '->' + data.state);
        $('#main').removeClass('printer-state-' + state.state).addClass('printer-state-' + data.state);
        if (page_ctx.on_change_state) {
          page_ctx.on_change_state(data.state);
        }
        $('#state-title').text(data.state);
        // if (on_change_state) {
        //     on_change_state( data.state );
        // }
        $('.enabled-on-printer-state-' + state.state).prop( "disabled", true );
        $('.enabled-on-printer-state-' + data.state).prop( "disabled", false );
        $('.disabled-on-printer-state-' + state.state).prop( "disabled", false );
        $('.disabled-on-printer-state-' + data.state).prop( "disabled", true );
    }

    $('#printer-pos').html(format_pos_x(data.pos_x) + '/' + format_pos_y(data.pos_y));
    state = data;
    if (page_ctx.on_update_state) {
      page_ctx.on_update_state(state);
    }
    if (state.progress) {
      
      let pr = (state.progress*100).toFixed(1) + '%';
      $('#state-progress').visible().children().first().css('width',pr).text(pr);
    } else {
      $('#state-progress').invisible();
    }
}

function load_state() {
    
  fetch('/api/state',{
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body:JSON.stringify(page_ctx.state_info || {})
      })
      .then(checkStatus)
      .then(parseJSON)
      .then(checkResultStatus)
      .then(function(data) {
        update_state(data);
      }).catch(function(error) {
        console.log('request failed', error);
      });   
    
}

function do_printer_action(action,data) {
  fetch('/api/action',{
      method:'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      },
      body:JSON.stringify({action:action,data:data})
    })
    .then(checkStatus)
    .then(parseJSON)
    .then(checkResultStatus)
    .then(function(data) {
       update_state(data);
    }).catch(function(error) {
        bootstrap_alert.error(
            '<p>Failed '+action+'</p>'+
            '<hr><p class="mb-0">' + error + '</p>'
          );
    })
}


