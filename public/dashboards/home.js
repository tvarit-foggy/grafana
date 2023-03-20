/* global _ */

'use strict';

return function (callback) {
  $.getJSON('/public/dashboards/home.json', function(data) {
    callback(data);
  });
};
