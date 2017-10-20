// @flow
import React, { Component, PropTypes } from 'react'
import classNames from 'classnames/bind'
import dateformat from 'dateformat'
import includes from 'lodash/includes'
import { Card } from './'
import InfiniteCalendar, { Calendar, defaultMultipleDateInterpolation, withMultipleDates } from 'react-infinite-calendar'
import 'react-infinite-calendar/styles.css'

const MultipleDatesCalendar = withMultipleDates(Calendar)

export class DatePicker extends Component {
  addDate: Function
  toggleDatePicker: Function
  state: Object

  static propTypes = {
    readOnly: PropTypes.bool,
    style: PropTypes.object,
    className: PropTypes.string,
    removeDate: PropTypes.func.isRequired,
    addDate: PropTypes.func.isRequired,
    dates: PropTypes.array.isRequired
  }

  constructor(props: any) {
    super(props)
    this.addDate = this.addDate.bind(this)
    this.toggleDatePicker = this.toggleDatePicker.bind(this)
    this.state = {
      showDatePicker: false
    }
  }

  removeDate(date: any) {
    return function(e) {
      this.props.removeDate(date)
      e.preventDefault()
    }.bind(this)
  }

  addDate(date: Date, isSelected: boolean, selectedDates: Date[]) {
    if (includes(this.props.dates, dateformat(date, 'yyyy-mm-dd'))) {
      this.props.removeDate(dateformat(date, 'yyyy-mm-dd'))
    } else {
      this.props.addDate(dateformat(date, 'yyyy-mm-dd'))
    }
  }

  toggleDatePicker(e: any) {
    this.setState({
      showDatePicker: !this.state.showDatePicker
    })
    e.preventDefault()
  }

  dateFromString(date: string) {
    const splitted = date.split('-')
    return new Date(splitted[0], splitted[1] - 1, parseInt(splitted[2]))
  }

  formatDate(date: string) {
    return dateformat(this.dateFromString(date), 'mmm dd, yyyy')
  }

  render() {
    const { className, style, dates, readOnly } = this.props
    return (
      <div>
        <div className={classNames(className, {'chips': true})} style={style}>
          { dates
            ? dates.map((date, index) =>
              <div className='chip' key={index}>
                { this.formatDate(date) }
                {
                  !readOnly
                  ? <i className='cross material-icons' onClick={this.removeDate(date)}>close</i>
                  : ''
                }
              </div>
            )
            : ''
          }
          {
            !readOnly
            ? <span className='right'>
              <a className='black-text' href='#' onClick={this.toggleDatePicker}><i className='material-icons'>today</i></a>
              { this.state.showDatePicker
                ? <div className='datepicker'>
                  <Card className='datepicker-card'>
                    <InfiniteCalendar
                      Component={MultipleDatesCalendar}
                      theme={{
                        accentColor: '#4CAF50',
                        floatingNav: {
                          background: 'rgba(245, 245, 245, 0.94)',
                          chevron: '#000',
                          color: '#000'
                        },
                        headerColor: '#FFF',
                        selectionColor: '#e0e0e0',
                        textColor: {
                          active: '#000',
                          default: '#333'
                        },
                        todayColor: '#e0e0e0',
                        weekdayColor: '#FFF'
                      }}
                      displayOptions={{
                        showHeader: true,
                        showWeekdays: true
                      }}
                      width='100%'
                      displayDate={false}
                      height={300}
                      interpolateSelection={defaultMultipleDateInterpolation}
                      selected={dates}
                      onSelect={this.addDate}
                    />
                  </Card>
                </div>
                : ''
              }
            </span>
            : ''
          }
        </div>
      </div>
    )
  }
}

