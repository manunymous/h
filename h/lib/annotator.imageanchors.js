// Generated by CoffeeScript 1.6.3
/*
** Annotator 1.2.6-dev-9424c6c
** https://github.com/okfn/annotator/
**
** Copyright 2012 Aron Carroll, Rufus Pollock, and Nick Stenning.
** Dual licensed under the MIT and GPLv3 licenses.
** https://github.com/okfn/annotator/blob/master/LICENSE
**
** Built at: 2013-11-18 16:47:30Z
*/



/*
//
*/

// Generated by CoffeeScript 1.6.3
(function() {
  var ImageAnchor, ImageHighlight, _ref,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  ImageHighlight = (function(_super) {
    __extends(ImageHighlight, _super);

    function ImageHighlight(anchor, pageIndex, image, shape, geometry) {
      ImageHighlight.__super__.constructor.call(this, anchor, pageIndex);
    }

    ImageHighlight.prototype.isTemporary = function() {
      return this._temporary;
    };

    ImageHighlight.prototype.setTemporary = function(value) {
      this._temporary = value;
      if (value) {

      } else {

      }
    };

    ImageHighlight.prototype.setActive = function(value) {
      if (value) {

      } else {

      }
    };

    ImageHighlight.prototype.removeFromDocument = function() {};

    ImageHighlight.prototype.annotationUpdated = function() {};

    ImageHighlight.prototype._getDOMElements = function() {};

    ImageHighlight.prototype.getTop = function() {};

    ImageHighlight.prototype.getHeight = function() {};

    ImageHighlight.prototype.getBottom = function() {};

    ImageHighlight.prototype.scrollTo = function() {};

    ImageHighlight.prototype.paddedScrollTo = function(direction) {};

    return ImageHighlight;

  })(Annotator.Highlight);

  ImageAnchor = (function(_super) {
    __extends(ImageAnchor, _super);

    function ImageAnchor(annotator, annotation, target, startPage, endPage, quote, image, shape, geometry) {
      this.image = image;
      this.shape = shape;
      this.geometry = geometry;
      ImageAnchor.__super__.constructor.call(this, annotator, annotation, target, startPage, endPage, quote);
    }

    ImageAnchor.prototype._createHighlight = function(page) {
      return new ImageHighlight(this, page, this.image, this.shape, this.geometry);
    };

    return ImageAnchor;

  })(Annotator.Anchor);

  Annotator.Plugin.ImageAnchors = (function(_super) {
    __extends(ImageAnchors, _super);

    function ImageAnchors() {
      this.showAnnotations = __bind(this.showAnnotations, this);
      this.createImageAnchor = __bind(this.createImageAnchor, this);
      _ref = ImageAnchors.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    ImageAnchors.prototype.pluginInit = function() {
      var image, wrapper, _i, _len, _ref1,
        _this = this;
      this.images = {};
      wrapper = this.annotator.wrapper[0];
      this.imagelist = $(wrapper).find('img');
      _ref1 = this.imagelist;
      for (_i = 0, _len = _ref1.length; _i < _len; _i++) {
        image = _ref1[_i];
        this.images[image.src] = image;
      }
      this.annotorious = new Annotorious.ImagePlugin(wrapper, {}, this, this.imagelist);
      this.annotator.anchoringStrategies.push({
        name: "image",
        code: this.createImageAnchor
      });
      return this.annotator.on('beforeAnnotationCreated', function(annotation) {
        if (_this.pendingID) {
          annotation.temporaryImageID = _this.pendingID;
          return delete _this.pendingID;
        }
      });
    };

    ImageAnchors.prototype.createImageAnchor = function(annotation, target) {
      var image, selector;
      selector = this.annotator.findSelector(target.selector, "ShapeSelector");
      if (selector == null) {
        return;
      }
      image = this.images[selector.source];
      if (!image) {
        return null;
      }
      return new ImageAnchor(this.annotator, annotation, target, 0, 0, '', image, selector.shapeType, selector.geometry);
    };

    ImageAnchors.prototype.annotate = function(source, shape, geometry, tempID) {
      var event;
      event = {
        targets: [
          {
            source: annotator.getHref(),
            selector: [
              {
                type: "ShapeSelector",
                source: source,
                shapeType: shape,
                geometry: geometry
              }
            ]
          }
        ]
      };
      this.pendingID = tempID;
      return this.annotator.onSuccessfulSelection(event, true);
    };

    ImageAnchors.prototype.showAnnotations = function(annotations) {
      return this.annotator.onAnchorClick(annotations);
    };

    return ImageAnchors;

  })(Annotator.Plugin);

}).call(this);

//
//@ sourceMappingURL=annotator.imageanchors.map