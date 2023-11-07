/* global _ */

'use strict';

return function (callback) {
  $.getJSON('/public/dashboards/documentation.json', function(data) {
    callback(data);
  });
};
